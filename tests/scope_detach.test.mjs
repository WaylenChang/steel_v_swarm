import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const json=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('scope detachment fixture retains source CSS and both fade directions',async()=>{
  const fixture=await json('tests/fixtures/scope_detach.json');
  const provenance=await json('data/provenance.json');
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.equal(fixture.programs.length,16);
  for(const channel of ['fire','weather'])for(const initial of [0,1]){
    const rows=fixture.programs.filter(p=>p.channel===channel&&p.initial===initial);
    assert.deepEqual(rows.map(p=>[p.time,p.flush]),[[.02,false],[.02,true],[.1,false],[.1,true]]);
    for(const p of rows){assert.ok(p.before>0&&p.before<1);assert.equal(p.after,1-initial);
      assert.equal(p.detachedAnimations,p.flush?0:null);assert.equal(p.reattachedAnimations,0);}
  }
});
