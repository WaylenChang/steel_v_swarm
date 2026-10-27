import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAudioMoveOscillators} from './audio_move_oscillator_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const [argument,...extra]=process.argv.slice(2),rate=Number(argument);
if(extra.length||!Number.isSafeInteger(rate)||rate<8000||rate>384000||String(rate)!==argument)
  throw new Error('Select one original movement oscillator rate from 8000 to 384000');
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const normalized=async name=>(await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n');
const parents={};
for(const [key,path]of Object.entries({movement:'data/audio_move_rates/'+rate+'.json',program:'data/audio_move_rate_waveforms/'+rate+'.json'})) {
  const bytes=await readFile(join(root,path));
  parents[key]={path,sha256:hash(bytes),value:JSON.parse(bytes)};
}
const movement=parents.movement.value,program=parents.program.value;
assert.deepEqual(program.source.movementProfile,{path:parents.movement.path,sha256:parents.movement.sha256});
assert.deepEqual(program.source.contextProfile,movement.source.contextProfile);
const inputs={...movement.source.inputs};
for(const [name,digest]of Object.entries(program.source.inputs)) {
  if(name in inputs)assert.equal(inputs[name],digest,'Consistent parent producer: '+name);
  inputs[name]=digest;
}
for(const name of ['tools/capture_audio_move_oscillators.mjs','tools/audio_move_oscillator_capture.mjs','tools/fixture_json.mjs']) {
  const digest=hash(await normalized(name));
  if(name in inputs)assert.equal(inputs[name],digest,'Consistent current producer: '+name);
  inputs[name]=digest;
}
const verify=async()=>{
  for(const parent of Object.values(parents))assert.equal(hash(await readFile(join(root,parent.path))),parent.sha256,'Parent changed: '+parent.path);
  assert.equal(hash(await readFile(join(root,movement.source.contextProfile.path))),movement.source.contextProfile.sha256);
  assert.deepEqual(program.source.sourceInputs,movement.source.sourceInputs);
  for(const [name,digest]of Object.entries(movement.source.sourceInputs))assert.equal(hash(await readFile(join(source,name))),digest,'Original changed: '+name);
  for(const [name,digest]of Object.entries(inputs))assert.equal(hash(await normalized(name)),digest,'Producer changed: '+name);
};
await verify();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
assert.ok(chromium,'Original oscillator capture requires Chromium');
const flags='--max-old-space-size=8192',browser=await chromium.launch({headless:true,executablePath:chromePath(),args:['--js-flags='+flags]});
try {
  for(const parent of [movement,program]) {
    assert.equal(browser.version(),parent.source.chromiumVersion);assert.equal(flags,parent.source.jsFlags);
  }
  const oscillators=await captureAudioMoveOscillators(await browser.newPage(),movement,program);
  await verify();
  const directory=join(root,'data/audio_move_oscillators');await mkdir(directory,{recursive:true});
  await writeFixtureJson(join(directory,rate+'.json'),{
    formatVersion:1,scope:'original-movement-isolated-oscillators',sampleRate:rate,frames:rate,
    parameterObservation:'constant-source-through-gain-with-identical-frequency-events',
    rateOscillatorsQualified:false,oscillators,
    source:{audioSha256:movement.source.audioSha256,sourceInputs:movement.source.sourceInputs,inputs,
      movementProfile:{path:parents.movement.path,sha256:parents.movement.sha256},
      programProfile:{path:parents.program.path,sha256:parents.program.sha256},contextProfile:movement.source.contextProfile,
      chromiumVersion:browser.version(),jsFlags:flags},
  });
  console.log('SOURCE_MOVE_OSCILLATORS_PASS '+JSON.stringify({sampleRate:rate,
    errors:oscillators.map(item=>({category:item.category,node:item.node,...item.modelErrors}))}));
} finally {await browser.close();}
