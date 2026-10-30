import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_fallback.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const png=value=>Buffer.from(value,'base64').subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'));

test('original cinematic image stack retains its fallback cases',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.ok(png(capture.textures.primary)&&png(capture.textures.fallback));
  assert.deepEqual(capture.cases.filter(item=>item.size===32).map(item=>item.name),['both','same','primary_missing','fallback_missing','no_fallback','both_missing']);
  assert.equal(capture.cases.length,12);
  for(const sample of capture.cases){
    assert.equal(sample.layerCount,sample.fallback?2:1);
    assert.ok(png(sample.png),sample.name);
  }
});
