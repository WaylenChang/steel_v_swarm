import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {decodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

const root=new URL('../',import.meta.url);
const captured=JSON.parse(await readFile(new URL('tests/fixtures/audio_scene_precision.json',root),'utf8'));
const words=part=>{
  const {bytes}=decodeSourceNumericPart(part),values=[];
  for(let offset=0;offset<bytes.length;offset+=8)values.push(bytes.readDoubleLE(offset));
  return values;
};

test('audio scene archive authenticates only the original methods actually executed',async()=>{
  assert.equal(captured.scope,'original-audio-scene-precision');
  const provenance=JSON.parse(await readFile(new URL('data/provenance.json',root),'utf8'));
  assert.deepEqual(Object.keys(captured.source.sourceInputs),['public/js/game.js','public/js/data.js','tools/audit_src.mjs']);
  for(const [path,hash]of Object.entries(captured.source.sourceInputs))assert.equal(provenance.inputs[path],hash);
  for(const [path,hash]of Object.entries(captured.source.inputs)) {
    const text=(await readFile(new URL(path,root),'utf8')).replace(/\r\n?/g,'\n');
    assert.equal(createHash('sha256').update(text).digest('hex'),hash,path);
  }
  assert.ok(captured.source.chromiumVersion);
});

test('strict range and nearest-source cases retain exact source parameters',()=>{
  const rotor=index=>captured.expected.movement[index].calls.find(value=>value.category==='rotor');
  assert.ok(words(rotor(0).parameters)[0]>0,'Exact 200 m remains audible');
  for(const index of [1,2,4])assert.equal(words(rotor(index).parameters)[0],0,'Double distance above 200 m rejects');
  assert.ok(words(rotor(3).parameters)[0]>0,'Previous native Float32 coordinate remains audible');
  assert.deepEqual(rotor(5),rotor(6),'Reversing distinct near-equal sources does not change the nearest winner');
  assert.notDeepEqual(rotor(5),rotor(7),'A genuine source tie still preserves encounter order');
  assert.equal(captured.expected.movement[10].calls.length,0,'Low-power mode does not publish movement targets');
  assert.equal(Object.keys(captured.characters).length,32);
  assert.equal(captured.expected.movement.length,369);
  const named=name=>captured.expected.movement[captured.programs.movement.findIndex(program=>program.name===name)];
  assert.deepEqual(named('stomp-nearest'),named('stomp-reversed'),'Winning ground queries are independent of distinct near-equal encounter order');
  assert.equal(words(named('stomp-nearest').calls.find(value=>value.category==='stomp').parameters)[3],1);
  for(const name of ['stomp-self','stomp-low'])assert.deepEqual(named(name).queries,[]);
  assert.equal(captured.expected.density.length,72);
  assert.equal(captured.expected.places.length,73);
});

test('all native boundary inputs and expected parameters use canonical Float64 frames',()=>{
  for(const program of captured.programs.movement) {
    for(const part of Object.values(program.camera))for(const value of words(part))assert.equal(Math.fround(value),value);
    if(program.ownWeights)assert.equal(words(program.ownWeights).length,2);
  }
  for(const program of [...captured.programs.movement,...captured.programs.places])for(const entity of program.entities) {
    for(const value of words(entity.mesh.position))assert.equal(Math.fround(value),value);
    if(entity.loco)assert.equal(words(entity.loco.w).length,3);
  }
  for(const part of captured.programs.positions)for(const value of words(part))assert.equal(Math.fround(value),value);
  for(const values of captured.expected.movement) {
    for(const value of values.calls)assert.equal(words(value.parameters).length,4);
    if(!Array.isArray(values.queries))assert.equal(words(values.queries).length%2,0);
  }
  for(const part of [...captured.expected.density,captured.expected.retained])assert.equal(words(part).length,2);
  for(const value of captured.expected.places)assert.equal(words(value.parameters).length,6);
});
