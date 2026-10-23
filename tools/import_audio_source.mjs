import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve,relative,isAbsolute} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAudioClips,audioCaptureBundles} from './audio_clip_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

// Refresh only the offline WebAudio captures after a complete source import.
// Source changes require the full importer, including its equivalence fixtures.
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||join(root,'..','steel_vs_swarm'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
if(!provenance.inputs||typeof provenance.inputs!=='object'||Array.isArray(provenance.inputs)||!Object.hasOwn(provenance.inputs,'public/js/audio.js'))
  throw new Error('Complete source provenance is required before refreshing audio');
for(const [name,expected]of Object.entries(provenance.inputs)) {
  const target=resolve(source,name),within=relative(source,target);
  if(isAbsolute(within)||within==='..'||within.startsWith('..\\')||within.startsWith('../')||typeof expected!=='string'||!/^[0-9a-f]{64}$/.test(expected))
    throw new Error('Invalid source provenance entry: '+name);
  const actual=createHash('sha256').update(await readFile(target)).digest('hex');
  if(actual!==expected)throw new Error('Source input changed; run the complete importer: '+name);
}
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Source audio capture requires the original development Playwright runtime');
const browser=await chromium.launch({headless:true,executablePath:chromePath(),args:['--js-flags=--max-old-space-size=8192']});
try {
  console.log('SOURCE_AUDIO_CAPTURE_BEGIN');
  const audio=await captureAudioClips(await browser.newPage(),source);
  for(const music of audio.music) {
    if(!Number.isFinite(music.maximumLoopError)||music.maximumLoopError>=.00002)
      throw new Error('Original music loop failed continuity: '+music.mood);
  }
  const bundles=audioCaptureBundles(audio);
  for(const [name,key]of Object.entries({audio_clips:'audioClips',audio_synth:'audioSynth',audio_music:'audioMusic',audio_move:'audioMove',audio_probes:'audioProbes'}))
    await writeFixtureJson(join(root,'data',name+'.json'),bundles[key]);
  console.log('SOURCE_AUDIO_CAPTURE_PASS '+JSON.stringify({sampleRate:audio.sampleRate,music:audio.music.map(({mood,maximumLoopError})=>({mood,maximumLoopError}))}));
} finally {await browser.close();}
