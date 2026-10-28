import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_hold_warning.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('buffered long presses cancel original hold feedback before warning or finishing',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/campaign_hold_warning_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.frames.length,11);
  for(const index of [2,5]){
    const frame=capture.frames[index];
    assert.equal(frame.active,false);
    assert.equal(frame.holding,false);
    assert.equal(frame.offset,2*Math.PI*26);
    assert.equal(frame.warnings,index===2?1:2);
    assert.equal(frame.destroyed,false);
  }
  assert.equal(capture.frames.at(-1).destroyed,true);
  assert.equal(capture.frames.at(-1).active,false);
});
