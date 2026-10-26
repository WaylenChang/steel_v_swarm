import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {captureAudioClips} from '../tools/audio_clip_capture.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const artifacts=join(root,'artifacts/sol/audio-sfx-rate-tests');
async function fixture() {
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'run-'));
  await mkdir(join(directory,'public/js'),{recursive:true});
  const original=await readFile(join(source,'public/js/audio.js'));
  await writeFile(join(directory,'public/js/audio.js'),original);
  return {directory,original};
}
function pageProbe() {
  const calls=[];
  return {calls,async evaluate(_callback,args) {
    calls.push(args);
    return {sampleRate:args.synthesisRate||47360,noise:{data:Buffer.alloc(8).toString('base64')}};
  }};
}

test('invalid SFX rates reject before reading source files or entering the browser',async()=>{
  for(const synthesisRate of [-1,1,7999,384001,48000.5,NaN,Infinity,'48000',null]) {
    const page=pageProbe();
    await assert.rejects(captureAudioClips(page,'missing-source',{synthesisRate}),/Invalid original SFX synthesis rate/);
    assert.equal(page.calls.length,0);
  }
});

test('SFX-only capture selects the requested context without sample assets or movement graphs',async()=>{
  const {directory,original}=await fixture(),page=pageProbe();
  const capture=await captureAudioClips(page,directory,{synthesisRate:48000});
  assert.equal(page.calls.length,1);
  assert.equal(page.calls[0].synthesisRate,48000);
  assert.deepEqual(page.calls[0].files,[]);
  assert.deepEqual(page.calls[0].moveGraphs,{});
  assert.deepEqual(capture.inputs,[]);
  assert.equal(capture.source.audioSha256,createHash('sha256').update(original.toString().replace(/\r\n?/g,'\n')).digest('hex'));
  assert.equal(capture.noise.sha256,createHash('sha256').update(Buffer.alloc(8)).digest('hex'));
});

test('the default capture still selects the complete sample and movement path',async()=>{
  const {directory}=await fixture(),page=pageProbe();
  await captureAudioClips(page,directory);
  assert.equal(page.calls[0].synthesisRate,0);
  assert.ok(page.calls[0].files.length>0);
  assert.ok(page.calls[0].files.every(file=>file.missing));
  assert.ok(Object.keys(page.calls[0].moveGraphs).length>0);
});

test('rate CLI rejects invalid or ambiguous selectors before source access and browser launch',async()=>{
  for(const args of [[],['0'],['7999'],['384001'],['48000.5'],['048000'],['48000','extra']])
    await assert.rejects(promisify(execFile)(process.execPath,[join(root,'tools/capture_audio_sfx_rate.mjs'),...args],
      {cwd:root,env:{...process.env,SVS_SOURCE:join(artifacts,'missing')},timeout:10000}),error=>{
      assert.match(error.stderr,/Select one original SFX synthesis rate/);
      assert.doesNotMatch(error.stderr,/ENOENT|Chromium/);
      return true;
    });
});
