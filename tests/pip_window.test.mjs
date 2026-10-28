import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_window.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('PiP window capture retains original source identities and framebuffer coordinates',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.equal(capture.runtime.webgl,'webgl2');
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/pip_window_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.cases.length,8);
  for(const row of capture.cases){
    assert.deepEqual(row.client,row.size);
    assert.deepEqual(row.backing,row.size.map(value=>value*row.dpr));
    assert.equal(row.pixelRatio,row.dpr);
    assert.equal(row.restored,true);
    assert.equal(row.borderPixels.length,4);
    assert.deepEqual(row.borderPixels,row.scissorPixels);
    assert.deepEqual(row.borderColor,[79,195,247,255]);
  }
  assert.deepEqual(capture.cases[0].borderPixels,[10,56,58,37]);
  assert.deepEqual(capture.cases[6].borderPixels,[10,56,126,80]);
  assert.deepEqual(capture.cases[7].borderPixels,[10,56,249,156]);
});
