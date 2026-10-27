import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_free.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const balance=JSON.parse(await read('data/balance.json'));

test('free spectator oracle retains its direct original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_free_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original browser preserves free movement and exact follow ties',()=>{
  assert.ok(capture.runtime.browser&&capture.runtime.userAgent);
  assert.deepEqual(capture.cameraRules,balance.spectator.camera);
  assert.deepEqual(capture.profile,balance.spectator.fallbacks.STEEL);
  assert.equal(capture.sequences.length,5);
  assert.equal(capture.sequences.reduce((sum,row)=>sum+row.frames.length,0),312);
  for(const sequence of capture.sequences)for(const frame of sequence.frames){
    for(let axis=0;axis<3;axis++){
      const value=Buffer.from(frame.positionBits[axis],'hex').readDoubleLE();
      const stored=Buffer.from(frame.positionFloat32Bits[axis],'hex').readFloatLE();
      assert.ok(Object.is(stored,Math.fround(value)));
    }
    if(frame.deltaBits)assert.equal(Buffer.from(frame.deltaBits,'hex').readDoubleLE(),frame.operation.advance);
  }
  for(const name of ['small-analog-follow-tie','small-analog-mode-tie']){
    const sequence=capture.sequences.find(row=>row.name===name);
    const selected=sequence.frames.find(row=>row.operation.follow===0||row.operation.select==='orbit');
    assert.equal(selected.pid,'1');
    assert.equal(Buffer.from(selected.positionBits[0],'hex').readDoubleLE(),1024+2**-14);
    assert.equal(Buffer.from(selected.positionFloat32Bits[0],'hex').readFloatLE(),1024);
  }
});
