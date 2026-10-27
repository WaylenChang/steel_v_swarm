import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_snap.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('spectator snap oracle retains direct original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_snap_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original anchor branch preserves strict threshold and locked views',()=>{
  assert.equal(capture.cases.length,16);
  for(const sample of capture.cases){
    assert.deepEqual(sample.anchor,sample.anchor.map(Math.fround));
    assert.deepEqual(sample.point,sample.point.map(Math.fround));
    assert.equal(Buffer.from(sample.distanceBits,'hex').readDoubleLE(),sample.distance);
    assert.equal(sample.result.snap,capture.cameraRules.LOCK_VIEWS.includes(sample.view)||!sample.anchorOk||sample.distance>capture.cameraRules.SNAP_M);
    if(sample.result.snap)assert.deepEqual(sample.result.anchor,sample.point);
    else if(!sample.delta)assert.deepEqual(sample.result.anchor,sample.anchor);
    else assert.notDeepEqual(sample.result.anchor,sample.anchor);
    assert.equal(sample.result.anchorOk,true);
  }
  const above=capture.cases.find(row=>row.name==='above-by-small-y');
  assert.ok(above.distance>capture.cameraRules.SNAP_M);
  assert.equal(Math.fround(above.distance),capture.cameraRules.SNAP_M);
  assert.equal(capture.cases.find(row=>row.name==='rounded-double-boundary').result.snap,false);
});
