import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {captureAudioMoveOscillators,oscillatorWitnessErrors} from '../tools/audio_move_oscillator_capture.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const movement=JSON.parse(await readFile(join(root,'data/audio_move_rates/48000.json'),'utf8'));
const program=JSON.parse(await readFile(join(root,'data/audio_move_rate_waveforms/48000.json'),'utf8'));
const encode=values=>{
  const bytes=Buffer.alloc(values.length*4);values.forEach((value,index)=>bytes.writeFloatLE(value,index*4));
  return bytes.toString('base64');
};
function pageProbe(change=value=>value) {
  const calls=[];
  return {calls,async evaluate(_callback,args) {
    calls.push(args);
    return change(args.inputs.map(input=>({...input,frames:args.sampleRate,
      values:encode(new Float32Array(args.sampleRate)),
      frequencyValues:encode(new Float32Array(args.sampleRate).fill(input.frequency))})));
  }};
}

test('isolated capture preserves original node targets, including non-invertible scalar products',async()=>{
  const page=pageProbe(),result=await captureAudioMoveOscillators(page,movement,program);
  assert.equal(page.calls.length,1);assert.equal(result.length,4);
  assert.equal(result.find(item=>item.category==='rotor').commands.length,3);
  assert.equal(result.find(item=>item.category==='stomp').commands[1].target,1.8);
  assert.equal(result.find(item=>item.category==='stomp').commands[1].parameterTarget,2.6*1.8);
  for(const item of result)for(const value of Object.values(item.modelErrors))assert.ok(Number.isFinite(value)&&value>=0);
});

test('mismatched source, scope, rates, bindings and command programs reject before browser access',async()=>{
  for(const change of [(_m,p)=>p.scope='invalid',(_m,p)=>p.sampleRate++,
    (_m,p)=>p.source.audioSha256='0'.repeat(64),(m)=>m.oscillators[0].type='invalid',
    (_m,p)=>p.waveforms.find(item=>item.category==='engine').commands.find(item=>item.key==='rate').parameterTarget++,
    (_m,p)=>p.waveforms.find(item=>item.category==='engine').commands.find(item=>item.key==='rate').tau=0,
    (_m,p)=>p.waveforms.find(item=>item.category==='engine').commands=p.waveforms.find(item=>item.category==='engine').commands.filter(item=>item.key!=='rate')]) {
    const m=structuredClone(movement),p=structuredClone(program),page=pageProbe();change(m,p);
    await assert.rejects(captureAudioMoveOscillators(page,m,p));assert.equal(page.calls.length,0);
  }
});

test('incomplete, reordered, nonfinite and noncanonical browser witnesses cannot be published',async()=>{
  for(const change of [items=>items.slice(1),items=>items.reverse(),
    items=>{items[0].frames--;return items;},items=>{items[0].values='';return items;},
    items=>{items[0].frequencyValues+='!';return items;},
    items=>{const bytes=Buffer.from(items[0].values,'base64');bytes.writeFloatLE(NaN,0);items[0].values=bytes.toString('base64');return items;},
    items=>{items[0].frequencyValues=encode(new Float32Array(48000).fill(48000));return items;}])
    await assert.rejects(captureAudioMoveOscillators(pageProbe(change),movement,program));
});

test('independent parameter observations isolate control error without replacing raw output or model bounds',()=>{
  const period={frames:4,frequency:1,values:encode([0,1,0,-1])};
  const witness={frames:4,values:period.values,frequencyValues:encode([1,1,1,1]),commands:[]};
  assert.deepEqual(oscillatorWitnessErrors(witness,period,4),
    {controlHz:0,scalarPeriod:0,measuredControlPeriod:0,roundedIncrementPeriod:0});
  const result=oscillatorWitnessErrors({...witness,frequencyValues:encode([1.5,1.5,1.5,1.5])},period,4);
  assert.equal(result.controlHz,.5);assert.equal(result.scalarPeriod,0);
  assert.ok(result.measuredControlPeriod>0);assert.ok(result.roundedIncrementPeriod>0);
});

test('oscillator CLI rejects ambiguous selectors before source or browser access',async()=>{
  for(const args of [[],['0'],['7999'],['384001'],['48000.5'],['048000'],['48000','extra']])
    await assert.rejects(promisify(execFile)(process.execPath,[join(root,'tools/capture_audio_move_oscillators.mjs'),...args],
      {cwd:root,env:{...process.env,SVS_SOURCE:'missing-source'},timeout:10000}),error=>{
      assert.match(error.stderr,/Select one original movement oscillator rate/);
      assert.doesNotMatch(error.stderr,/ENOENT|Chromium/);return true;
    });
});

test('archived raw witnesses retain current provenance and independently reproducible model errors',async()=>{
  const captured=JSON.parse(await readFile(join(root,'data/audio_move_oscillators/48000.json'),'utf8'));
  assert.equal(captured.rateOscillatorsQualified,false);
  assert.equal(captured.parameterObservation,'constant-source-through-gain-with-identical-frequency-events');
  const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
  for(const parent of [captured.source.movementProfile,captured.source.programProfile,captured.source.contextProfile])
    assert.equal(hash(await readFile(join(root,parent.path))),parent.sha256);
  for(const [name,digest]of Object.entries(captured.source.inputs))
    assert.equal(hash((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n')),digest);
  assert.equal(captured.oscillators.length,movement.oscillators.length);
  for(const [index,witness]of captured.oscillators.entries()) {
    const period=movement.oscillators[index],values=Buffer.from(witness.frequencyValues,'base64');
    assert.equal(values.readFloatLE(0),Math.fround(period.frequency));
    assert.equal(values.readFloatLE(6000*4),Math.fround(period.frequency));
    assert.ok(values.readFloatLE(6001*4)<values.readFloatLE(6000*4));
    assert.deepEqual(oscillatorWitnessErrors(witness,period,captured.sampleRate),witness.modelErrors);
    assert.equal(witness.modelErrors.scalarPeriod,program.periodErrors[witness.category+':'+witness.node]);
  }
});
