import {readFile,mkdir,mkdtemp,unlink,rmdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {audioReferences} from './audio_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';
import {partitionFixtures} from './fixture_sections.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const audio=await readFile(join(source,'public/js/audio.js'));
const sourceInputs={'public/js/audio.js':digest(audio)};
if(sourceInputs['public/js/audio.js']!==provenance.inputs['public/js/audio.js'])
  throw new Error('Original audio module changed; refresh shared source metadata first');
// Reuse the original recorder, publishing only its independent manager programs.
const data=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const recorded=await audioReferences(source,data);
const inputs={};
for(const path of ['tools/audio_manager_references.mjs','tools/audio_references.mjs',
  'tools/audio_scene_references.mjs','tools/audio_move_references.mjs','tools/audio_music_references.mjs',
  'tools/audio_ambience_references.mjs','tools/audio_native_references.mjs','tools/local_fire_references.mjs',
  'tools/fixture_json.mjs','tools/fixture_sections.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
if(digest(await readFile(join(source,'public/js/audio.js')))!==sourceInputs['public/js/audio.js'])
  throw new Error('Original audio module changed during manager capture');
const values={source:{formatVersion:1,inputs,sourceInputs}};
for(const key of ['audioGates','audioCounts','audioSamples']) {
  if(!Array.isArray(recorded.fixtures[key])||recorded.fixtures[key].length===0)
    throw new Error('Missing original manager programs: '+key);
  values[key]=recorded.fixtures[key];
}
await mkdir(join(root,'build'),{recursive:true});
await mkdir(join(root,'data/audio_manager'),{recursive:true});
const staging=await mkdtemp(join(root,'build/audio-manager-'));
const raw=join(staging,'source.json');
await writeFixtureJson(raw,values);
await partitionFixtures(raw,join(root,'data/audio_manager/fixtures.json'));
await unlink(raw);
await rmdir(staging);
console.log('AUDIO_MANAGER_REFERENCES_PASS '+JSON.stringify(Object.fromEntries(
  Object.entries(values).filter(([key])=>key!=='source').map(([key,value])=>[key,value.length]))));
