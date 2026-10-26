import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {audioMoveReferences} from './audio_move_references.mjs';
import {captureMoveBank} from './audio_move_capture.mjs';
import {captureFilterImpulses} from './audio_synth_capture.mjs';

const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

export async function captureAudioMoveRate(page,profile,original) {
  assert.equal(profile?.scope,'original-sfx-synthesis-rate-only','Original SFX context profile');
  const rate=profile.sampleRate,noise=profile.noise;
  assert.ok(Number.isSafeInteger(rate)&&rate>=8000&&rate<=384000,'Original context sample rate');
  assert.equal(digest(original.replace(/\r\n?/g,'\n')),profile.source.audioSha256,'Same original audio module');
  assert.equal(noise?.sampleRate,rate,'Shared noise context rate');
  assert.equal(noise.frames,rate,'Original one-second noise');
  assert.equal(noise.encoding,'float32le','Original noise encoding');
  assert.equal(typeof noise.data,'string','Original noise storage');
  const bytes=Buffer.from(noise.data,'base64');
  assert.equal(bytes.length,rate*4,'Complete original noise words');
  assert.equal(bytes.toString('base64'),noise.data,'Canonical original noise encoding');
  assert.equal(digest(bytes),noise.sha256,'Original SFX noise fingerprint');
  for(let offset=0;offset<bytes.length;offset+=4)assert.ok(Number.isFinite(bytes.readFloatLE(offset)),'Finite original noise words');
  const graphs=audioMoveReferences(original).graphs;
  const result=await page.evaluate(async({graphs,noise,captureSource,filterSource})=>{
    const bytes=Uint8Array.from(atob(noise.data),value=>value.charCodeAt(0));
    const view=new DataView(bytes.buffer),values=new Float32Array(noise.frames);
    for(let index=0;index<values.length;index++)values[index]=view.getFloat32(index*4,true);
    const context=new OfflineAudioContext(1,1,noise.sampleRate);
    const shared=context.createBuffer(1,noise.frames,noise.sampleRate);
    shared.copyToChannel(values,0);
    // Continue the captured context's noise generation; never call _buildNoise again.
    const move=await new Function('return ('+captureSource+');')()(graphs,shared);
    const filters=await new Function('return ('+filterSource+');')()(
      Object.values(graphs).flatMap(graph=>graph.nodes.filter(node=>node.kind==='createBiquadFilter')));
    return {move,filters};
  },{graphs,noise,captureSource:captureMoveBank.toString(),filterSource:captureFilterImpulses.toString()});
  assert.equal(result.move.noise.values,noise.data,'Movement retains every original SFX noise bit');
  assert.equal(result.move.noise.sampleRate,rate);
  assert.equal(result.move.noise.frames,rate);
  const expected=Object.entries(graphs).flatMap(([category,graph])=>graph.nodes
    .filter(node=>node.kind==='createOscillator').map(node=>category+':'+node.id)).sort();
  assert.deepEqual(result.move.oscillators.map(item=>item.category+':'+item.node).sort(),expected,'Complete original movement oscillators');
  for(const oscillator of result.move.oscillators) {
    const raw=Buffer.from(oscillator.values,'base64');
    assert.ok(Number.isSafeInteger(oscillator.frames)&&oscillator.frames>=2);
    assert.ok(Number.isFinite(oscillator.sampleRate)&&oscillator.sampleRate>=8000&&oscillator.sampleRate<=384000);
    assert.equal(raw.length,oscillator.frames*4);
    assert.equal(raw.toString('base64'),oscillator.values);
    for(let offset=0;offset<raw.length;offset+=4)assert.ok(Number.isFinite(raw.readFloatLE(offset)));
  }
  return {sampleRate:rate,noiseSha256:noise.sha256,graphs,...result.move,filters:result.filters};
}
