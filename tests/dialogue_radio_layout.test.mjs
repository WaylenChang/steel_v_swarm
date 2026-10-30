import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const json=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('radio layout fixture preserves source identity and responsive boundaries',async()=>{
  const fixture=await json('tests/fixtures/dialogue_radio_layout.json');
  const data=await json('data/dialogue_radio_layout.json');
  const provenance=await json('data/provenance.json');
  assert.deepEqual(data,{formatVersion:fixture.formatVersion,source:fixture.source,rules:fixture.rules});
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.equal(fixture.programs.length,27);
  assert.deepEqual([...new Set(fixture.programs.map(p=>p.viewport[0]))],[320,360,500,720,721,825,826,1024,1440]);
  for(const p of fixture.programs){
    const r=p.viewport[0]<=fixture.rules.mobileMaxWidth?fixture.rules.mobile:fixture.rules.desktop;
    assert.deepEqual(p.padding,r.padding);assert.deepEqual(p.border,r.border);
    assert.equal(p.bottom,r.bottom);assert.equal(p.gap,r.gap);assert.equal(p.rowGap,r.rowGap);assert.equal(p.avatar,r.avatar);
    assert.equal(p.box[1]+p.box[3]+r.bottom,p.viewport[1]);
  }
});
