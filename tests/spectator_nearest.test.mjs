import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_nearest.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('spectator nearest oracle keeps its direct original source identities',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_nearest_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original nearest selection preserves distinctions and stable exact ties',()=>{
  assert.equal(capture.cases.length,18);
  for(const sample of capture.cases){
    for(const point of [sample.camera,...sample.rows.map(row=>row.position)])
      assert.deepEqual(point,point.map(Math.fround));
    for(const distance of sample.distances)
      assert.equal(Buffer.from(distance.bits,'hex').readDoubleLE(),distance.value);
    assert.deepEqual(sample.result.roster,['1','2']);
    assert.equal(sample.result.pid,sample.distances[0].value<=sample.distances[1].value?'1':'2');
    assert.equal(sample.result.mode,'fpv');
    assert.equal(sample.result.anchorOk,false);
  }
  const sample=capture.cases.find(row=>row.name==='xy-near-tie'&&row.action==='follow');
  assert.ok(sample.distances[0].value>sample.distances[1].value);
  assert.equal(Math.fround(sample.distances[0].value),Math.fround(sample.distances[1].value));
  assert.deepEqual(capture.groupCases.map(row=>[row.name,row.action,row.result.pid]),[
    ['nearest-not-last','follow','2'],['nearest-not-last','mode','2'],
    ['later-exact-tie','follow','2'],['later-exact-tie','mode','2'],
    ['side-and-bot-order','follow','10'],['side-and-bot-order','mode','10']]);
  assert.deepEqual(capture.edgeCases.map(row=>[row.name,row.pid]),
    [['nan-first','2'],['nan-second','2'],['infinity-first','2'],['infinity-second','1'],['equal-infinities','1']]);
});
