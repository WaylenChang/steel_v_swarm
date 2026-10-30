import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const root=fileURLToPath(new URL('..',import.meta.url));
const readJson=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('portrait fixture retains original CSS and current capture identities',async()=>{
  const fixture=await readJson('tests/fixtures/dialogue_portrait.json');
  const data=await readJson('data/dialogue_portrait.json');
  const provenance=await readJson('data/provenance.json');
  assert.deepEqual(data,{formatVersion:fixture.formatVersion,source:fixture.source,rules:fixture.rules});
  for(const [path,hash] of Object.entries(fixture.source.inputs)){
    const text=(await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n');
    assert.equal(digest(text),hash,path);
  }
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.deepEqual(fixture.rules,{active:1,inactive:.35,duration:.18});
  assert.equal(fixture.programs.length,8);
  for(const initial of [false,true]){
    const programs=fixture.programs.filter(p=>p.initial===initial);
    assert.equal(programs.length,4);
    assert.ok(programs.every(p=>p.initialOpacity===(initial?1:.35)));
    assert.ok(programs.some(p=>p.frames.some(f=>f.duration>0&&f.duration<fixture.rules.duration)));
    assert.ok(programs.some(p=>p.frames.some(f=>f.time>0&&f.opacity>.35&&f.opacity<1)));
  }
});
