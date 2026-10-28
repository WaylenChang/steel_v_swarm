import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_window_precision.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('minimap window capture retains original methods and imported bounds',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/minimap_window_precision_capture.mjs','data/maps.json','data/balance.json']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/game.js','public/js/data.js','public/index.html','tools/audit_src.mjs']);
  for(const [path,expected]of Object.entries(capture.source.inputs)){
    const bytes=await read(path);
    assert.equal(digest(path.endsWith('.mjs')?bytes.toString('utf8').replace(/\r\n?/g,'\n'):bytes),expected,path);
  }
  for(const [path,expected]of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.cases.length,448);
  assert.deepEqual(new Set(capture.cases.map(row=>row.map)),new Set(['berlin','taroko','dubai','walvisbay','narrow-axis','zero-axis','tiny-axis']));
  assert.ok(capture.cases.some(row=>row.near)&&capture.cases.some(row=>!row.near));
  assert.ok(capture.cases.every(row=>row.projections.length===5&&row.cropBits.length===4&&row.componentsBits.length===4));
  assert.ok(capture.cases.some(row=>row.reveal?.hard&&row.reveal?.soft));
  assert.ok(capture.cases.some(row=>row.map==='tiny-axis'&&row.near&&row.label==='周遭 0m'));
});
