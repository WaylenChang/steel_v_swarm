import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/player_tps_anchor.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('TPS anchor capture retains the original program and native-representable inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/player_tps_anchor_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.cases.length,720);
  for(const row of capture.cases){
    assert.deepEqual(row.point,row.point.map(Math.fround));
    assert.equal(row.queryBits.length,3);
    assert.equal(row.cameraBits.length,3);
  }
  assert.ok(capture.cases.some(row=>row.floor===null));
  assert.ok(capture.cases.some(row=>row.floor===50&&row.queryBits[1]!==row.cameraBits[1]));
  const highFloor=Buffer.alloc(4);
  highFloor.writeFloatLE(50+capture.rules.FLOOR_M);
  for(const row of capture.cases){
    if(row.floor===null)assert.deepEqual(row.cameraBits,row.queryBits);
    if(row.floor===50){
      assert.equal(row.cameraBits[0],row.queryBits[0]);
      assert.equal(row.cameraBits[1],highFloor.toString('hex'));
      assert.equal(row.cameraBits[2],row.queryBits[2]);
    }
  }
});
