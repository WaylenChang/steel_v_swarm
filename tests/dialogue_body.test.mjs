import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const read=path=>readFileSync(new URL('../'+path,import.meta.url));
const capture=JSON.parse(read('tests/fixtures/dialogue_body.json'));
test('native transcript geometry is sealed to its original CSS and capture program',()=>{
  assert.deepEqual(JSON.parse(read('data/dialogue_body.json')),{formatVersion:1,source:capture.source,rules:capture.rules});
  const provenance=JSON.parse(read('data/provenance.json'));
  for(const [path,hash]of Object.entries(capture.source.inputs))assert.equal(createHash('sha256').update(read(path).toString('utf8').replace(/\r\n?/g,'\n')).digest('hex'),hash);
  for(const [path,hash]of Object.entries(capture.source.sourceInputs))assert.equal(provenance.inputs[path],hash);
});
test('controlled rows cover scrolling, intrinsic height, fractional caps and responsive art',()=>{
  assert.equal(capture.programs.length,28);
  for(const width of [360,720,721,1440])assert.ok(capture.programs.some(p=>p.viewport.width===width));
  assert.ok(capture.programs.some(p=>p.viewport.height===32));
  assert.ok(capture.programs.some(p=>!Number.isInteger(p.state.script[3])));
  for(const p of capture.programs){
    assert.equal(p.state.rows.length,p.heights.length);
    assert.deepEqual(p.state.padding,capture.rules.padding);
    assert.equal(p.state.gap,capture.rules.gap);
    assert.equal(p.state.artVisible,p.viewport.width>capture.rules.artMaxHiddenWidth);
    assert.equal(p.state.body[3],p.state.script[3]);
    p.heights.forEach((height,index)=>assert.equal(p.state.rows[index][3],height));
  }
});
