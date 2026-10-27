import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {captureAudioMoveWaveforms} from '../tools/audio_move_waveform_capture.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const movement=JSON.parse(await readFile(join(root,'data/audio_move_rates/48000.json'),'utf8'));
const original=await readFile(join(source,'public/js/audio.js'),'utf8');

test('source waveform capture covers each static graph and dry/blended/wet stomp',async()=>{
  let calls=0;
  const page={async evaluate(_callback,args){calls++;return args;}};
  const result=await captureAudioMoveWaveforms(page,movement,original);
  assert.equal(calls,1);assert.equal(result.movement.noise.values,movement.noise.values);
  assert.equal(result.cases.length,6);
  assert.deepEqual(result.cases.filter(item=>item.category==='stomp').map(item=>item.wet),[0,.65,1]);
});

test('automation capture explicitly selects the original movement program mode',async()=>{
  const page={async evaluate(_callback,args){return args;}};
  const result=await captureAudioMoveWaveforms(page,movement,original,{automation:true});
  assert.equal(result.automation,true);assert.equal(result.cases.length,6);
  await assert.rejects(captureAudioMoveWaveforms(page,movement,original,{automation:'true'}));
});

test('rate capture explicitly includes the original variable-frequency program',async()=>{
  const page={async evaluate(_callback,args){return args;}};
  const result=await captureAudioMoveWaveforms(page,movement,original,{automation:true,rates:true});
  assert.equal(result.automation,true);assert.equal(result.rates,true);
  await assert.rejects(captureAudioMoveWaveforms(page,movement,original,{rates:true}));
});

test('source waveform capture rejects another source or noise before browser execution',async()=>{
  for(const change of [value=>value.source.audioSha256='f'.repeat(64),value=>value.noiseSha256='0'.repeat(64),
    value=>value.noise.frames--,value=>value.scope='invalid']) {
    const invalid=structuredClone(movement);change(invalid);
    await assert.rejects(captureAudioMoveWaveforms({async evaluate(){assert.fail('No browser execution for invalid source');}},invalid,original));
  }
});

test('waveform CLI rejects ambiguous rates before source and browser access',async()=>{
  for(const args of [[],['0'],['7999'],['384001'],['48000.5'],['048000'],['48000','extra'],['48000','--automation','extra'],['48000','--rates','--automation']])
    await assert.rejects(promisify(execFile)(process.execPath,[join(root,'tools/capture_audio_move_waveforms.mjs'),...args],
      {cwd:root,env:{...process.env,SVS_SOURCE:'missing-source'},timeout:10000}),error=>{
      assert.match(error.stderr,/Select one original movement waveform rate/);
      assert.doesNotMatch(error.stderr,/ENOENT|Chromium/);return true;
    });
});
