import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {decodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

const root=new URL('../',import.meta.url);
const capture=JSON.parse(await readFile(new URL('tests/fixtures/touch_precision.json',root),'utf8'));
const words=part=>{
  const {bytes}=decodeSourceNumericPart(part),values=[];
  for(let offset=0;offset<bytes.length;offset+=8)values.push(bytes.readDoubleLE(offset));
  return values;
};
const gesture=name=>capture.expected.gestures[capture.gestures.findIndex(program=>program.name===name)];

test('touch precision archive authenticates original handlers and both executed source inputs',async()=>{
  assert.equal(capture.scope,'original-touch-native-boundary-precision');
  const provenance=JSON.parse(await readFile(new URL('data/provenance.json',root),'utf8'));
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/mobile.js','tools/audit_src.mjs']);
  for(const [path,hash]of Object.entries(capture.source.sourceInputs))assert.equal(provenance.inputs[path],hash);
  for(const [path,hash]of Object.entries(capture.source.inputs)) {
    const text=(await readFile(new URL(path,root),'utf8')).replace(/\r\n?/g,'\n');
    assert.equal(createHash('sha256').update(text).digest('hex'),hash,path);
  }
  assert.ok(capture.source.chromiumVersion);
  assert.equal(capture.sticks.length,992);
  assert.equal(capture.gestures.length,48);
  assert.equal(words(capture.ruleValues).length,capture.ruleNames.length);
});

test('original tap slop and drag-fire decisions retain genuine two-axis distances',()=>{
  const exact=gesture('button-release:16,0');
  assert.deepEqual(exact.at(-1).events,[{type:'command',action:'reload',on:true}]);
  for(const kind of ['button-release','button-return']) {
    const outside=gesture(kind+':16,'+Math.fround(.001));
    assert.deepEqual(outside.at(-1).events,[],'A tiny second-axis displacement must still cancel a tap');
  }
  const outside=gesture('tap-near:16,'+Math.fround(.001));
  assert.equal(outside[2].state.fireArm,false);
  assert.deepEqual(outside.at(-1).events,[],'A rejected second tap never becomes held fire');
  const inside=gesture('drag-fire:'+Math.fround(7.999999523162842)+','+Math.fround(.002));
  assert.equal(inside[3].events.some(event=>event.type==='command'&&event.action==='fire'&&event.on),false);
  assert.deepEqual(gesture('cancel').at(-1).events,[]);
});

test('all source scalars retain canonical Float64 storage and native pointer dimensions',()=>{
  for(const input of capture.sticks) {
    const values=words(input.values);
    assert.equal(values.length,7);
    for(const value of values.slice(0,4))assert.equal(Math.fround(value),value);
  }
  const frame=value=>{
    assert.equal(words(value.state.scalars).length,6);
    assert.equal(words(value.state.axis).length,2);
    assert.equal(words(value.state.clocks).length,2);
    assert.ok(value.state.taps.every(Number.isSafeInteger));
    for(const event of value.events)if(event.type==='look')assert.equal(words(event.source).length,2);
  };
  for(const value of capture.expected.sticks) {
    frame(value.active);frame(value.released);
    assert.deepEqual(words(value.released.state.scalars),[0,0,0,0,0,0]);
    assert.ok(Object.is(words(value.released.state.axis)[1],-0));
  }
  for(const value of capture.expected.gestures)for(const row of value)frame(row);
  for(const value of capture.gestures)for(const step of value.steps)assert.equal(words(step.values).length,4);
});
