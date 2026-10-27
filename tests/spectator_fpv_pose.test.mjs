import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_fpv_pose.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const balance=JSON.parse(await read('data/balance.json'));

test('spectator FPV pose oracle retains direct original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_fpv_pose_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original browser retains controlled spectator FPV poses',()=>{
  assert.ok(capture.runtime.browser&&capture.runtime.userAgent);
  assert.deepEqual(capture.camera,balance.spectator.camera);
  assert.equal(capture.actors.length,7);
  assert.equal(capture.cases.length,588);
  for(const actor of capture.actors)
    assert.deepEqual(actor.profile,actor.character?balance.spectator.profiles[actor.character]:balance.spectator.fallbacks.STEEL);
  assert.ok(capture.cases.some(row=>row.altitude===capture.camera.FLY_M));
  assert.ok(capture.cases.some(row=>row.altitude>capture.camera.FLY_M));
  for(const sample of capture.cases){
    assert.deepEqual(sample.point,sample.point.map(Math.fround));
    assert.ok(Number.isFinite(Buffer.from(sample.yawBits,'hex').readDoubleLE()));
    assert.equal(sample.hidden,true);
    assert.equal(sample.visible,false);
    for(let axis=0;axis<3;axis++){
      const value=Buffer.from(sample.cameraBits[axis],'hex').readDoubleLE();
      const stored=Buffer.from(sample.cameraFloat32Bits[axis],'hex').readFloatLE();
      assert.ok(Object.is(stored,Math.fround(value)));
    }
  }
});
