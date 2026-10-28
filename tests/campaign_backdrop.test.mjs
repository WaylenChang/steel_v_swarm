import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_backdrop.json'));
const data=JSON.parse(await read('data/campaign_backdrop.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic backdrop retains its inset and scaled browser geometry',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/campaign_backdrop_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{inset:30,scale:1.12});
  assert.equal(capture.cases.length,12);
  for(const row of capture.cases){
    assert.deepEqual(row.stage,[0,0,...row.size]);
    assert.deepEqual(row.layout,row.size.map(value=>value+60));
    assert.match(row.filter,/blur\(36px\)/);
  }
});
