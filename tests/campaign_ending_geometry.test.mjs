import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_ending_geometry.json'));
const data=JSON.parse(await read('data/campaign_ending_geometry.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic ending spacing controls crawl height and focus',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{padding:{top:30,right:0,bottom:20,left:0},dividerGap:8,noteGap:20});
  assert.equal(capture.programs.length,3);
  for(const program of capture.programs){
    assert.deepEqual(program.inline,program.controlled);
    assert.deepEqual(program.section,{top:0,height:200});
    assert.equal(program.endingTop,224);
    assert.deepEqual(program.inline,{height:158,divider:{top:30,height:20},note:{top:58,height:20},
      button:{top:98,height:40},scrollHeight:382});
    assert.equal(program.frames.length,6);
    assert.equal(program.frames.at(-1).scroll,282);
  }
});
