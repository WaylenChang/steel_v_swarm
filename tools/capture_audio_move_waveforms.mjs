import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAudioMoveWaveforms} from './audio_move_waveform_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const [argument,...extra]=process.argv.slice(2),rate=Number(argument);
if(extra.length||!Number.isSafeInteger(rate)||rate<8000||rate>384000||String(rate)!==argument)
  throw new Error('Select one original movement waveform rate from 8000 to 384000');
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const normalized=async path=>(await readFile(path,'utf8')).replace(/\r\n?/g,'\n');
const parentPath='data/audio_move_rates/'+rate+'.json',parentBytes=await readFile(join(root,parentPath));
const parent=JSON.parse(parentBytes),original=await readFile(join(source,'public/js/audio.js'));
assert.deepEqual(parent.source.sourceInputs,{'public/js/audio.js':hash(original)});
assert.equal(hash(await readFile(join(root,parent.source.contextProfile.path))),parent.source.contextProfile.sha256);
const inputs={...parent.source.inputs};
for(const name of ['tools/capture_audio_move_waveforms.mjs','tools/audio_move_waveform_capture.mjs','tools/fixture_json.mjs']) {
  const digest=hash(await normalized(join(root,name)));
  if(name in inputs)assert.equal(digest,inputs[name]);
  inputs[name]=digest;
}
const verify=async()=>{
  assert.equal(hash(await readFile(join(source,'public/js/audio.js'))),hash(original),'Original audio changed during capture');
  assert.equal(hash(await readFile(join(root,parentPath))),hash(parentBytes),'Movement context changed during capture');
  assert.equal(hash(await readFile(join(root,parent.source.contextProfile.path))),parent.source.contextProfile.sha256,'SFX context changed during capture');
  for(const [name,digest]of Object.entries(inputs))assert.equal(hash(await normalized(join(root,name))),digest,'Producer changed: '+name);
};
await verify();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original movement waveform capture requires Chromium');
const flags='--max-old-space-size=8192',browser=await chromium.launch({headless:true,executablePath:chromePath(),args:['--js-flags='+flags]});
try {
  assert.equal(browser.version(),parent.source.chromiumVersion);
  assert.equal(flags,parent.source.jsFlags);
  const result=await captureAudioMoveWaveforms(await browser.newPage(),parent,original.toString());
  assert.equal(result.waveforms.length,6);
  assert.deepEqual(Object.keys(result.periodErrors).sort(),parent.oscillators.map(item=>item.category+':'+item.node).sort());
  for(const fixture of result.waveforms)for(const channel of fixture.channels) {
    const bytes=Buffer.from(channel,'base64');assert.equal(bytes.length,rate*4);
    for(let offset=0;offset<bytes.length;offset+=4)assert.ok(Number.isFinite(bytes.readFloatLE(offset)));
  }
  for(const value of Object.values(result.periodErrors))assert.ok(Number.isFinite(value)&&value>=0);
  await verify();
  await mkdir(join(root,'data/audio_move_waveforms'),{recursive:true});
  await writeFixtureJson(join(root,'data/audio_move_waveforms',rate+'.json'),{
    formatVersion:1,scope:'original-movement-static-waveforms',...result,
    source:{audioSha256:parent.source.audioSha256,sourceInputs:parent.source.sourceInputs,inputs,
      movementProfile:{path:parentPath,sha256:hash(parentBytes)},contextProfile:parent.source.contextProfile,
      chromiumVersion:browser.version(),jsFlags:flags},
  });
  console.log('SOURCE_MOVE_WAVEFORMS_PASS '+JSON.stringify({sampleRate:rate,cases:result.waveforms.length,periodErrors:result.periodErrors}));
} finally {await browser.close();}
