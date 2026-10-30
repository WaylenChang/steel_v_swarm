import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const json=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('radio text fixture retains original dialogue and responsive CSS',async()=>{
  const fixture=await json('tests/fixtures/dialogue_radio_text.json');
  const data=await json('data/dialogue_radio_text.json');
  const provenance=await json('data/provenance.json');
  assert.deepEqual(data,{formatVersion:fixture.formatVersion,source:fixture.source,rules:fixture.rules});
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.deepEqual(fixture.programs.map(p=>p.viewport[0]),[320,720,721,1440]);
  for(const program of fixture.programs){
    assert.deepEqual(program.frames.map(frame=>frame.speaker),['t06','s01','m01','t06']);
    assert.deepEqual(program.frames.map(frame=>frame.text),program.frames.map(frame=>frame.input));
    for(const frame of program.frames){
      assert.equal(frame.speakerFont,fixture.rules.speakerFont);assert.equal(frame.gap,fixture.rules.gap);
      assert.equal(frame.lineFont,program.viewport[0]<=fixture.rules.mobileMaxWidth?fixture.rules.mobileLineFont:fixture.rules.desktopLineFont);
      assert.equal(frame.lineHeight/frame.lineFont,fixture.rules.lineHeightRatio);
      assert.deepEqual(frame.lineColor,fixture.rules.lineColor);
    }
  }
});
