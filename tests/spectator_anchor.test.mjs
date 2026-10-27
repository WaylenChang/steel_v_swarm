import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_anchor.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const balance=JSON.parse(await read('data/balance.json'));

test('spectator anchor oracle retains direct original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_anchor_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original browser retains multi-frame smoothing and reset decisions',()=>{
  assert.ok(capture.runtime.browser&&capture.runtime.userAgent);
  assert.deepEqual(capture.cameraRules,balance.spectator.camera);
  assert.equal(capture.sequences.length,5);
  assert.equal(capture.sequences.reduce((sum,row)=>sum+row.frames.length,0),454);
  for(const sequence of capture.sequences){
    let valid=sequence.anchorOk;
    for(const frame of sequence.frames){
      assert.deepEqual(frame.point,frame.point.map(Math.fround));
      if(Object.hasOwn(frame,'setAnchorOk'))valid=frame.setAnchorOk;
      const distance=Buffer.from(frame.distanceBits,'hex').readDoubleLE();
      assert.equal(Buffer.from(frame.deltaBits,'hex').readDoubleLE(),frame.delta);
      const exponential=Buffer.from(frame.exponentialBits,'hex').readDoubleLE();
      const alpha=Buffer.from(frame.alphaBits,'hex').readDoubleLE();
      assert.equal(alpha,1-exponential);
      assert.ok(Number.isFinite(Buffer.from(frame.argumentBits,'hex').readDoubleLE()));
      assert.equal(frame.snap,capture.cameraRules.LOCK_VIEWS.includes(frame.view)||!valid||distance>capture.cameraRules.SNAP_M);
      assert.equal(frame.anchorOk,true);
      for(let axis=0;axis<3;axis++){
        const value=Buffer.from(frame.anchorBits[axis],'hex').readDoubleLE();
        const stored=Buffer.from(frame.anchorFloat32Bits[axis],'hex').readFloatLE();
        assert.ok(Object.is(stored,Math.fround(value)));
      }
      valid=frame.anchorOk;
    }
  }
  const slow=capture.sequences.find(row=>row.name==='small-motion-240');
  assert.notEqual(slow.frames[27].anchorFloat32Bits[0],slow.frames[0].anchorFloat32Bits[0]);
  assert.equal(slow.frames.at(-1).snap,true);
});
