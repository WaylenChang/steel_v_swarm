import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_death_selection.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original death view selects the stable nearest live tower, then first base',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>[row.name,row.rendered,row.selected]),[
    ['nearest-tower',true,2],['later-tie',true,1],['first-tie',true,1],['dead-and-no-mesh',true,3],
    ['first-base-even-dead',true,2],['base-with-mesh',true,3],['fallback',true,null],['precision-near-tie',true,2],['hidden-source',true,1],
    ['nonfinite-then-finite',true,3],['nonfinite-base-fallback',true,3],
    ['missing-side',false,null],['alive',false,null],['transition',false,null],['game-over',false,null],
    ['missing-config',false,null],['missing-frame',false,null],['hidden-frame',false,null],['small-frame',false,null]]);
  assert.ok(capture.programs.every(row=>row.restored));
});
