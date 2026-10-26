import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {captureMoveBank} from '../tools/audio_move_capture.mjs';

const graphs=JSON.parse(await readFile(new URL('../data/audio_move_rates/48000.json',import.meta.url),'utf8')).graphs;
const noise={sampleRate:48000,length:48000,getChannelData:()=>new Float32Array(48000)};
function renderer(t) {
  const previous=globalThis.OfflineAudioContext;
  globalThis.OfflineAudioContext=class {
    constructor(_channels,frames,rate){this.frames=frames;this.rate=rate;this.destination={};}
    createOscillator(){return {frequency:{value:0},detune:{value:0},connect(){},start(){}};}
    async startRendering(){return {sampleRate:this.rate,getChannelData:()=>new Float32Array(this.frames)};}
  };
  t.after(()=>{globalThis.OfflineAudioContext=previous;});
}

test('legacy movement capture retains its original single-period representation',async t=>{
  renderer(t);
  const result=await captureMoveBank(graphs,noise),engine=result.oscillators.find(item=>item.category==='engine');
  assert.equal(engine.frames,1043);assert.equal(engine.sampleRate,47978);assert.equal(engine.cycles,undefined);
});

test('native tonal capture retains complete 46 Hz cycles without a fractional context rate',async t=>{
  renderer(t);
  const result=await captureMoveBank(graphs,noise,{nativeRate:true});
  const engine=result.oscillators.find(item=>item.category==='engine');
  assert.equal(engine.frames,24000);assert.equal(engine.sampleRate,48000);assert.equal(engine.cycles,23);
  for(const item of result.oscillators.filter(item=>item.category!=='engine'))assert.equal(item.cycles,undefined);
});

test('unsupported fractional tonal frequencies reject instead of substituting a period',async t=>{
  renderer(t);
  const changed=structuredClone(graphs);changed.engine.nodes.find(node=>node.kind==='createOscillator').parameters.frequency.initial=46.5;
  await assert.rejects(captureMoveBank(changed,noise,{nativeRate:true}),/Unsupported exact native movement oscillator period/);
});
