import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_scrollbar.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic scrollbar keeps its CSS width and browser coverage',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.style,{width:4,color:'rgba(95, 208, 242, 0.25)',radius:2});
  assert.equal(capture.programs.length,17);
  assert.deepEqual(capture.programs[1].thumb,{top:37,height:25});
  assert.deepEqual(capture.programs[3].thumb,{top:0,height:17});
  assert.deepEqual(capture.programs[7].thumb,{top:0,height:17});
  assert.deepEqual(capture.programs[13].thumb,{top:0,height:12});
  assert.equal(capture.programs[8].thumb,null);
  for(const sample of capture.programs){
    assert.deepEqual(sample.style,capture.style);
    assert.equal(sample.clientWidth,sample.size[0]-(sample.contentHeight>sample.size[1]?capture.style.width:0));
    assert.equal(sample.scroll,Math.min(sample.requested,Math.max(0,sample.contentHeight-sample.size[1])));
    assert.deepEqual([...Buffer.from(sample.png,'base64').subarray(0,8)],[137,80,78,71,13,10,26,10]);
  }
});
