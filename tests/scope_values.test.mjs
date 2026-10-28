import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/scope_values.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('scope values retain original HUD callbacks and browser serialization',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/scope_values_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/data.js','public/js/main.js','tools/audit_src.mjs']);
  for(const [path,expected]of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected]of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.ok(capture.browser);
  for(const group of ['grid','weather-boundary','radius-boundary','blur-boundary'])
    assert.ok(capture.samples.some(sample=>sample.group===group),group);
  for(const sample of capture.samples){
    assert.ok(Number.isFinite(sample.radius)&&Number.isFinite(sample.blur));
    for(const key of ['fire','weather','radius','blur']){
      assert.match(sample[key+'Bits'],/^[0-9a-f]{16}$/);
      assert.equal(Buffer.from(sample[key+'Bits'],'hex').readDoubleLE(),sample[key]);
    }
    if(sample.weather>0) {
      assert.ok(sample.gradient);
      if(sample.scoped)assert.equal(sample.gradient.outer,sample.radius);
      else assert.equal(sample.gradient.stops.length,2);
    }
  }
  assert.equal(capture.programs.length,2);
  for(const program of capture.programs){
    assert.equal(program.length,4);
    assert.equal(program[1].gradient.background,program[0].gradient.background);
    assert.equal(program[2].gradient.background,program[0].gradient.background);
    assert.equal(program[2].gradient.scoped,program[0].gradient.scoped);
    assert.notEqual(program[3].gradient.background,program[0].gradient.background);
  }
  assert.notEqual(capture.programs[1][1].radius,capture.programs[1][1].gradient.stops[1]);
});
