import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_publication.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('PiP selection follows received decoy snapshots, not intermediate authority state',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/pip_publication_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/game.js','server/sim.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.steps.map(row=>[row.action,row.selected]),[
    ['snapshot-empty',[]],['spawn-7',[]],['publish-7',[7]],['lose-7',[7]],['publish-lost',[]],
    ['recover-7',[]],['publish-recovered',[7]],['spawn-9',[7]],['publish-two',[7,9]],
    ['remove-7',[7,9]],['publish-9',[9]]]);
});
