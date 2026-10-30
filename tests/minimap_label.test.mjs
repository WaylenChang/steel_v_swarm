import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_label.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original minimap legend keeps measured text and browser rasters',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.cases.map(row=>row.text),['全部','周遭 0m','周遭 1m','周遭 140m','周遭 680m','周遭 10001m']);
  for(const sample of capture.cases){
    assert.equal(sample.font,'10px monospace');assert.equal(sample.baseline,'bottom');assert.equal(sample.align,'left');
    assert.ok(sample.textWidth>0);
    assert.equal(Buffer.from(sample.png,'base64').subarray(0,8).toString('hex'),'89504e470d0a1a0a');
  }
});
