import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAudioPan} from './audio_pan_capture.mjs';
import {captureFilterImpulses} from './audio_synth_capture.mjs';
import {audioMoveReferences} from './audio_move_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const raw=await readFile(join(source,'public/js/audio.js'));
const script=raw.toString('utf8').replace(/\r\n?/g,'\n');
const synthesisBytes=await readFile(join(root,'data/audio_synth.json'));
const synthesis=JSON.parse(synthesisBytes);
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
if(synthesis.formatVersion!==1||!Array.isArray(synthesis.sounds)||synthesis.source?.audioSha256!==digest(script)
  ||provenance.inputs?.['public/js/audio.js']!==digest(raw))
  throw new Error('Original audio source changed; refresh its source capture before mixer verification');
const move=audioMoveReferences(script);
const effects=[...synthesis.sounds.flatMap(sound=>sound.stems.flatMap(stem=>stem.effects)),
  ...Object.values(move.graphs).flatMap(graph=>graph.nodes.filter(node=>node.kind==='createBiquadFilter'))];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Mixer references require the original development Playwright runtime');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage();
  const audioPan=await captureAudioPan(page,source);
  const audioFilters=await page.evaluate(async({effects,capture})=>
    new Function('return ('+capture+');')()(effects),{effects,capture:captureFilterImpulses.toString()});
  if(audioPan.length!==21||!audioFilters.length)throw new Error('Incomplete original mixer impulse references');
  if(digest(await readFile(join(source,'public/js/audio.js')))!==digest(raw))
    throw new Error('Original audio source changed during mixer capture');
  const inputs={};
  for(const name of ['tools/audio_mixer_references.mjs','tools/audio_pan_capture.mjs','tools/audio_synth_capture.mjs','tools/audio_move_references.mjs'])
    inputs[name]=digest((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n'));
  await writeFixtureJson(join(root,'data/audio_mixer.json'),{formatVersion:1,
    source:{audioSha256:digest(script),synthesisSha256:digest(synthesisBytes),inputs},audioPan,audioFilters});
  console.log('AUDIO_MIXER_REFERENCES_PASS '+JSON.stringify({panning:audioPan.length,filters:audioFilters.length,rates:[44100,48000,96000]}));
} finally {await browser.close();}
