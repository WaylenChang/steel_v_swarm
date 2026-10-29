import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_header.json'));
const data=JSON.parse(await read('data/campaign_header.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic header retains responsive padding and border',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules.landscape,{top:8,right:16,bottom:6,left:16});
  assert.deepEqual(capture.rules.portrait,{top:7,right:12,bottom:5,left:12});
  assert.equal(capture.rules.borderWidth,1);
  assert.deepEqual(capture.rules.background,[6/255,10/255,16/255,.25]);
  assert.deepEqual(capture.rules.border,[122/255,158/255,178/255,.15]);
  assert.equal(capture.cases.length,4);
});
