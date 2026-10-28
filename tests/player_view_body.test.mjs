import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/player_view_body.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('body-turn capture retains the exact original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/player_view_body_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('body-turn corpus covers both sides of the original strict threshold',()=>{
  assert.equal(capture.cases.length,15);
  for(const sample of capture.cases){
    assert.deepEqual(sample.move,sample.move.map(Math.fround));
    assert.equal(sample.movementSquared,sample.move[0]**2+sample.move[1]**2+sample.move[2]**2);
    assert.equal(sample.frames.length,12);
  }
  const below=capture.cases.find(row=>row.name==='below-float-rounds-up');
  const above=capture.cases.find(row=>row.name==='above-float-rounds-down');
  const nativeSquared=move=>Math.fround(Math.fround(move[0]*move[0])+
    Math.fround(move[1]*move[1])+Math.fround(move[2]*move[2]));
  assert.ok(below.movementSquared<capture.threshold&&nativeSquared(below.move)>capture.threshold);
  assert.ok(above.movementSquared>capture.threshold&&nativeSquared(above.move)<capture.threshold);
  assert.ok(below.frames.every(yaw=>yaw===below.initialYaw));
  assert.notEqual(above.frames[0],above.initialYaw);
});
