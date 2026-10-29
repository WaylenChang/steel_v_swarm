import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_crawl_mask.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original crawl viewport masks both edges after composing its content',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.mask,'linear-gradient(rgba(0, 0, 0, 0) 0%, rgb(0, 0, 0) 4%, rgb(0, 0, 0) 95%, rgba(0, 0, 0, 0) 100%)');
  assert.equal(capture.programs.length,6);
  for(const program of capture.programs){
    assert.equal(program.layers.length,2);
    assert.deepEqual([...Buffer.from(program.png,'base64').subarray(0,8)],[137,80,78,71,13,10,26,10]);
  }
});
