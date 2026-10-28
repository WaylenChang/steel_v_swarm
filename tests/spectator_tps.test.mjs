import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_tps.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const balance=JSON.parse(await read('data/balance.json'));

test('spectator third-person oracle retains direct original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_tps_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original browser retains third-person positions and clipping decisions',()=>{
  assert.ok(capture.runtime.browser&&capture.runtime.userAgent);
  assert.deepEqual(capture.cameraRules,balance.spectator.camera);
  assert.equal(capture.cases.filter(row=>row.kind==='clear').length,630);
  assert.equal(capture.cases.filter(row=>row.kind==='clip').length,24);
  assert.equal(capture.sequence.frames.length,48);
  for(const actor of capture.actors)
    assert.deepEqual(actor.profile,actor.character?balance.spectator.profiles[actor.character]:balance.spectator.fallbacks.STEEL);
  const clipped=capture.cases.filter(row=>row.kind==='clip'&&row.beforeBits.some((value,index)=>value!==row.pulledBits[index]));
  assert.ok(clipped.some(row=>row.hit===4));
  assert.ok(clipped.some(row=>row.ridge&&row.hit===null));
  for(const frame of [...capture.cases,...capture.sequence.frames]){
    assert.deepEqual(frame.point,frame.point.map(Math.fround));
    assert.ok(Number.isFinite(Buffer.from(frame.yawBits,'hex').readDoubleLE()));
    assert.ok(Number.isFinite(Buffer.from(frame.pitchBits,'hex').readDoubleLE()));
    assert.ok(frame.samples>=1&&frame.samples<=12);
    for(const key of ['aim','before','pulled'])for(let axis=0;axis<3;axis++){
      const value=Buffer.from(frame[key+'Bits'][axis],'hex').readDoubleLE();
      const stored=Buffer.from(frame[key+'Float32Bits'][axis],'hex').readFloatLE();
      assert.ok(Object.is(stored,Math.fround(value)));
    }
  }
  assert.notDeepEqual(capture.sequence.frames[0].beforeBits,capture.sequence.frames.at(-1).beforeBits);
});
