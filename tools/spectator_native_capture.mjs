import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {cameraReferences} from './camera_references.mjs';
import {spectatorReferences} from './spectator_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/game.js','public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js',
  'public/js/rng.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const data=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const game=await readFile(join(source,'public/js/game.js'),'utf8');
const camera=await cameraReferences(data,source,game);
const capture=await spectatorReferences(data,source,game,camera.heroView,
  {captureRotation:true,extraAngles:[20000.12345,-20000.12345]});
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during spectator capture: '+file);
const inputs={};
for(const file of ['tools/spectator_native_capture.mjs','tools/spectator_references.mjs','tools/camera_references.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/spectator_native.json'),{formatVersion:1,
  source:{inputs,sourceInputs},metadata:capture.rules,...capture.fixtures});
console.log('SPECTATOR_NATIVE_REFERENCES_PASS programs='+capture.fixtures.spectatorPrograms.length+' hud='+capture.fixtures.spectatorHud.length);
