import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAudioMoveRate} from './audio_move_rate_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const [argument,...extra]=process.argv.slice(2),rate=Number(argument);
if(extra.length||!Number.isSafeInteger(rate)||rate<8000||rate>384000||String(rate)!==argument)
  throw new Error('Select one original movement context rate from 8000 to 384000');
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const normalized=async path=>(await readFile(path,'utf8')).replace(/\r\n?/g,'\n');
const profilePath='data/audio_sfx_rates/'+rate+'.json';
const profileBytes=await readFile(join(root,profilePath));
const profile=JSON.parse(profileBytes);
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const original=await readFile(join(source,'public/js/audio.js'));
assert.equal(digest(original),provenance.inputs['public/js/audio.js'],'Imported original audio module');
assert.deepEqual(profile.source.sourceInputs,{'public/js/audio.js':digest(original)},'Original context source inputs');
const producers=['tools/capture_audio_move_rate.mjs','tools/audio_move_rate_capture.mjs',
  'tools/audio_move_references.mjs','tools/audio_move_capture.mjs','tools/audio_synth_capture.mjs','tools/fixture_json.mjs'];
const inputs={...profile.source.inputs};
for(const name of producers) {
  const hash=digest(await normalized(join(root,name)));
  if(name in inputs)assert.equal(hash,inputs[name],'Shared context producer is current: '+name);
  inputs[name]=hash;
}
for(const [name,hash]of Object.entries(inputs))assert.equal(digest(await normalized(join(root,name))),hash,'Current producer: '+name);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original movement rate capture requires Chromium');
const flags='--max-old-space-size=8192';
const browser=await chromium.launch({headless:true,executablePath:chromePath(),args:['--js-flags='+flags]});
try {
	assert.equal(browser.version(),profile.source.chromiumVersion,'Same source audio renderer as the SFX context capture');
	assert.equal(flags,profile.source.jsFlags,'Same source renderer flags');
  const movement=await captureAudioMoveRate(await browser.newPage(),profile,original.toString());
  assert.equal(digest(await readFile(join(source,'public/js/audio.js'))),digest(original),'Original audio changed during capture');
  assert.equal(digest(await readFile(join(root,profilePath))),digest(profileBytes),'Original context profile changed during capture');
  for(const [name,hash]of Object.entries(inputs))assert.equal(digest(await normalized(join(root,name))),hash,'Producer changed during capture: '+name);
  const directory=join(root,'data/audio_move_rates');
  await mkdir(directory,{recursive:true});
  await writeFixtureJson(join(directory,rate+'.json'),{
    formatVersion:1,scope:'original-movement-shared-sfx-rate',...movement,
    source:{audioSha256:profile.source.audioSha256,sourceInputs:profile.source.sourceInputs,
      contextProfile:{path:profilePath,sha256:digest(profileBytes)},inputs,
      chromiumVersion:browser.version(),jsFlags:flags},
  });
  console.log('SOURCE_MOVE_RATE_PASS '+JSON.stringify({sampleRate:rate,oscillators:movement.oscillators.length,
    filters:movement.filters.length,noiseSha256:movement.noiseSha256,sharedSfxContext:true}));
} finally {await browser.close();}
