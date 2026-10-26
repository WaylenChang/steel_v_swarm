import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAudioClips} from './audio_clip_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const [argument,...extra]=process.argv.slice(2),rate=Number(argument);
if(extra.length||!Number.isSafeInteger(rate)||rate<8000||rate>384000||String(rate)!==argument)
  throw new Error('Select one original SFX synthesis rate from 8000 to 384000');
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const read=async name=>JSON.parse(await readFile(join(root,'data',name),'utf8'));
const [provenance,balance]=await Promise.all([read('provenance.json'),read('balance.json')]);
const original=await readFile(join(source,'public/js/audio.js'));
assert.equal(digest(original),provenance.inputs['public/js/audio.js'],'Imported original audio module');
const producerFiles=['tools/capture_audio_sfx_rate.mjs','tools/audio_clip_capture.mjs','tools/audio_synth_capture.mjs','tools/fixture_json.mjs'];
const inputs=Object.fromEntries(await Promise.all(producerFiles.map(async name=>
  [name,digest((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n'))])));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original SFX rate capture requires Chromium');
const flags='--max-old-space-size=8192';
const browser=await chromium.launch({headless:true,executablePath:chromePath(),args:['--js-flags='+flags]});
try {
  const audio=await captureAudioClips(await browser.newPage(),source,{synthesisRate:rate});
  const expected=[...balance.audio.synthesisIds].sort(),ids=audio.synth.sounds.map(sound=>sound.id).sort();
  assert.deepEqual(ids,expected,'Complete original synthesis IDs');
  assert.equal(audio.sampleRate,rate);
  assert.equal(audio.synthProbes.length,expected.length*4);
  for(const id of expected)assert.deepEqual(audio.synthProbes.filter(probe=>probe.id===id).map(probe=>probe.gain),[.06,.4,1,1.4]);
  assert.ok(audio.synth.sounds.every(sound=>sound.sampleRate===rate&&sound.frames>0&&sound.stems.length>0));
  assert.ok(audio.synthProbes.every(probe=>probe.sampleRate===rate&&probe.frames>0&&probe.channels.length===2));
  assert.equal(Buffer.from(audio.noise.data,'base64').length,audio.noise.frames*4);
  assert.equal(digest(Buffer.from(audio.noise.data,'base64')),audio.noise.sha256);
  assert.deepEqual(audio.inputs,[],'Synthesis-only capture does not consume sample assets');
  assert.equal(audio.music.length,0,'Synthesis-only capture does not execute procedural music');
  assert.equal(audio.move,null,'Synthesis-only capture does not execute movement synthesis');
  assert.equal(digest(await readFile(join(source,'public/js/audio.js'))),digest(original),'Original audio changed during capture');
  for(const name of producerFiles)assert.equal(digest((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n')),inputs[name],'Producer changed during capture');
  const directory=join(root,'data/audio_sfx_rates');
  await mkdir(directory,{recursive:true});
  await writeFixtureJson(join(directory,rate+'.json'),{
    formatVersion:1,scope:'original-sfx-synthesis-rate-only',sampleRate:rate,
    source:{audioSha256:audio.source.audioSha256,sourceInputs:{'public/js/audio.js':digest(original)},
      inputs,chromiumVersion:browser.version(),jsFlags:flags},
    noise:audio.noise,sounds:audio.synth.sounds,filters:audio.synth.filters,probes:audio.synthProbes,
  });
  console.log('SOURCE_SFX_RATE_PASS '+JSON.stringify({sampleRate:rate,sounds:ids.length,probes:audio.synthProbes.length,filters:audio.synth.filters.length}));
} finally {await browser.close();}
