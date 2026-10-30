import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('original minimap shadow boundary and source identity',async()=>{
  const fixture=await read('tests/fixtures/minimap_shadow_boundary.json');
  const provenance=await read('data/provenance.json');
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.deepEqual(fixture.cases.map(row=>[row.name,row.shadows?.length??null]),[
    ['no-blockers',null],['inside-hypot-boundary',1],['inside',0],['ordinary',1],
    ['outside-range',0],['too-small',0],['translated',1]]);
  const blocker=fixture.cases[1].blockers[0];
  assert.ok(Math.hypot(blocker.x,blocker.z)>blocker.r);
  assert.equal(Math.sqrt(blocker.x*blocker.x+blocker.z*blocker.z),blocker.r);
});
