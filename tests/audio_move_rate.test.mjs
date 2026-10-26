import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {captureAudioMoveRate} from '../tools/audio_move_rate_capture.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const profile=JSON.parse(await readFile(join(root,'data/audio_sfx_rates/48000.json'),'utf8'));
const original=await readFile(join(source,'public/js/audio.js'),'utf8');
const oscillators=JSON.parse(await readFile(join(root,'data/audio_move.json'),'utf8')).oscillators;
function pageProbe(change=result=>result) {
  const calls=[];
  return {calls,async evaluate(_callback,args) {
    calls.push(args);
    return change({move:{noise:{sampleRate:args.noise.sampleRate,frames:args.noise.frames,
      encoding:'float32le',values:args.noise.data},oscillators:structuredClone(oscillators)},filters:[]});
  }};
}

test('movement capture reuses the complete original SFX context buffer',async()=>{
  const page=pageProbe(),result=await captureAudioMoveRate(page,profile,original);
  assert.equal(page.calls.length,1);
  assert.equal(page.calls[0].noise.data,profile.noise.data);
  assert.equal(result.noiseSha256,profile.noise.sha256);
  assert.equal(result.noise.values,profile.noise.data);
  assert.equal(result.sampleRate,48000);
  assert.deepEqual(Object.keys(result.graphs).sort(),['engine','rotor','stomp','wingflap']);
});

test('invalid context identities and raw noise reject before browser evaluation',async()=>{
  for(const change of [value=>value.scope='invalid',value=>value.sampleRate=44100,
    value=>value.noise.sha256='f'.repeat(64),value=>value.noise.encoding='float64le',
    value=>value.noise.frames--,value=>value.source.audioSha256='0'.repeat(64),
    value=>value.noise.data='!'+value.noise.data.slice(1)]) {
    const invalid=structuredClone(profile),page=pageProbe();
    change(invalid);
    await assert.rejects(captureAudioMoveRate(page,invalid,original));
    assert.equal(page.calls.length,0);
  }
});

test('movement output cannot substitute another noise generation or omit an oscillator',async()=>{
  for(const change of [result=>{result.move.noise.values='';return result;},
    result=>{result.move.oscillators.pop();return result;},
    result=>{result.move.oscillators[0].values='';return result;}])
    await assert.rejects(captureAudioMoveRate(pageProbe(change),profile,original));
});

test('movement rate CLI rejects ambiguous selectors before source or browser access',async()=>{
  for(const args of [[],['0'],['7999'],['384001'],['48000.5'],['048000'],['48000','extra']])
    await assert.rejects(promisify(execFile)(process.execPath,[join(root,'tools/capture_audio_move_rate.mjs'),...args],
      {cwd:root,env:{...process.env,SVS_SOURCE:'missing-source'},timeout:10000}),error=>{
      assert.match(error.stderr,/Select one original movement context rate/);
      assert.doesNotMatch(error.stderr,/ENOENT|Chromium/);
      return true;
    });
});
