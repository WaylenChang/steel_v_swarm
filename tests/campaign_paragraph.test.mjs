import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_paragraph.json'));
const data=JSON.parse(await read('data/campaign_paragraph.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic paragraphs retain their text and responsive margins',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{landscapeGap:8,portraitGap:6,
    font:{min:13.5,offset:6.5,vmin:1.05,max:16.5},colour:[230/255,238/255,245/255,1]});
  assert.equal(capture.cases.length,7);
  for(const sample of capture.cases){
    const rule=capture.rules.font;
    const expected=Math.min(rule.max,Math.max(rule.min,Math.min(...sample.size)*rule.vmin/100+rule.offset));
    assert.ok(Math.abs(sample.fontSize-expected)<0.0001,`${sample.size}`);
  }
  assert.deepEqual(capture.programs.map(program=>program.kind),['prologue','steel','swarm']);
  for(const program of capture.programs){
    assert.ok(program.sections.length>0);
    for(const section of program.sections)
      assert.ok(section.id&&section.paragraphs.length>0&&section.paragraphs.every(text=>text.length>0));
  }
});
