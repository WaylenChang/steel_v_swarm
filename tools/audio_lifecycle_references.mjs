import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {audioReferences} from './audio_references.mjs';
import {captureAudioAmbience} from './audio_ambience_capture.mjs';
import {localFeedbackReferences} from './local_feedback_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const name of ['public/js/audio.js','public/js/game.js','public/js/data.js','public/js/botPolicy.js',
  'public/js/balancePrefs.js','public/js/rng.js','public/index.html','public/js/main.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,name));
  if(provenance.inputs?.[name]!==digest(bytes))throw new Error('Source input changed; refresh shared source metadata first: '+name);
  sourceInputs[name]=digest(bytes);
}
const data=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const references=await audioReferences(source,data);
const fixtures={};
for(const key of ['audioMusicLifecycle','audioAmbienceLifecycle','audioMoveLifecycle','audioMoveCategories',
  'audioSceneMovement','audioSceneDensity','audioScenePlaces','localFire']) {
  if(!references.fixtures[key])throw new Error('Missing original audio lifecycle reference: '+key);
  fixtures[key]=references.fixtures[key];
}
fixtures.localFeedback=(await localFeedbackReferences(source)).mixed;
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Audio lifecycle references require the original development Playwright runtime');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  fixtures.audioAmbienceEnvelope=await captureAudioAmbience(await browser.newPage(),source);
  for(const [name,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,name)))!==expected)throw new Error('Source changed during lifecycle capture: '+name);
  const inputs={};
  for(const name of ['tools/audio_lifecycle_references.mjs','tools/audio_references.mjs','tools/audio_scene_references.mjs',
    'tools/audio_move_references.mjs','tools/audio_music_references.mjs','tools/audio_ambience_references.mjs',
    'tools/audio_ambience_capture.mjs','tools/audio_native_references.mjs','tools/local_fire_references.mjs','tools/local_feedback_references.mjs'])
    inputs[name]=digest((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n'));
  await writeFixtureJson(join(root,'data/audio_lifecycle.json'),{formatVersion:1,source:{inputs,sourceInputs},fixtures});
  console.log('AUDIO_LIFECYCLE_REFERENCES_PASS '+JSON.stringify(Object.fromEntries(Object.entries(fixtures)
    .map(([key,value])=>[key,Array.isArray(value)?value.length:1]))));
} finally {await browser.close();}
