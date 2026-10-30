import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const json=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('radio note fixture retains original dialogue method and CSS',async()=>{
  const fixture=await json('tests/fixtures/dialogue_radio_note.json');
  const data=await json('data/dialogue_radio_note.json');
  const provenance=await json('data/provenance.json');
  assert.deepEqual(data,{formatVersion:fixture.formatVersion,source:fixture.source,rules:fixture.rules});
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.equal(fixture.programs.length,4);
  assert.deepEqual(fixture.rules,{fontSize:11,gap:10,noteColor:[1,1,1,.45]});
  for(const program of fixture.programs){
    assert.deepEqual(program.frames.map(frame=>frame.speaker),['t06','s01','m01']);
    for(const frame of program.frames){
      assert.equal(frame.title,program.title);assert.equal(frame.note,program.note);
      assert.equal(frame.combined,program.title+program.note);
      assert.deepEqual(frame.noteColor,fixture.rules.noteColor);
    }
    assert.equal(new Set(program.frames.map(frame=>JSON.stringify(frame.titleColor))).size,3);
  }
});
