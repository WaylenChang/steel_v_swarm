import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_finish_button.json'));
const data=JSON.parse(await read('data/campaign_finish_button.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original finish-button dimensions retain CSS selector precedence',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{padding:{top:14,right:24,bottom:14,left:24},
    border:{top:1,right:1,bottom:1,left:1},fontSize:16,letterSpacing:5,cursor:'pointer'});
  assert.equal(capture.programs.length,9);
  for(const sample of capture.programs){
    assert.deepEqual(sample.rules,capture.rules);
    assert.deepEqual(sample.button,[sample.contentSize[0]+50,sample.contentSize[1]+30]);
    assert.deepEqual(sample.content,[25,15,...sample.contentSize]);
  }
});
