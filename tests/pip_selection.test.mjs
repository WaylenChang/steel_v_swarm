import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_selection.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('PiP selection capture retains the original render-time program',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/pip_selection_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/game.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.scenarios.length,2);
  for(const scenario of capture.scenarios){
    const a=scenario.drone?20:7,b=scenario.drone?21:9,c=scenario.drone?22:11,d=scenario.drone?23:13;
    assert.deepEqual(scenario.steps.slice(0,10).map(row=>row.selected),[
      [a,b],[b],[],[c],[c,d],[c,d],[c,d],[c],[c,d],[a,c]]);
    if(!scenario.drone)assert.deepEqual(scenario.steps[10].selected,[a,c]);
    assert.deepEqual(scenario.steps.at(-1).selected,[c,d]);
    assert.equal(scenario.steps.find(row=>row.phase==='replace-model').rows.find(row=>row.id===c).modelRevision,1);
    for(const row of scenario.steps){
      assert.equal(row.restored,true);
      assert.deepEqual(row.draws.map(draw=>draw.id),row.selected);
    }
  }
});
