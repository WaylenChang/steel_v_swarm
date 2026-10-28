import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_heading.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('spectator heading capture retains direct original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/spectator_heading_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/game.js','public/js/data.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.cases.length,300);
  for(const sample of capture.cases){
    const delta=Buffer.from(sample.deltaBits,'hex').readDoubleLE();
    if(delta<=0||sample.kind==='null'||sample.kind==='missing')assert.equal(sample.resultBits,sample.initialBits);
  }
});
