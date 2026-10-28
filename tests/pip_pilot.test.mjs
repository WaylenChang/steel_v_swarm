import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_pilot.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('PiP pilot capture retains the original render-time selection and source inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/pip_pilot_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/game.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.cases.map(row=>[row.phase,row.selected]),[
    ['alive',[7,9]],['dead',[]],['revived',[7,9]],['no-side',[]]]);
  for(const row of capture.cases){
    assert.equal(row.draws.length,row.selected.length);
    assert.equal(row.restored,true);
    for(let i=0;i<row.draws.length;i++)assert.deepEqual(row.draws[i],{hidden:[row.selected[i]],cockpit:false});
  }
});
