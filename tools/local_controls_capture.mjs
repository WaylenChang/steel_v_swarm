import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {localCastReferences} from './local_cast_references.mjs';
import {localDefenseReferences} from './local_defense_references.mjs';
import {localStatusReferences} from './local_status_references.mjs';
import {controlEffectReferences} from './control_effect_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const name of ['public/js/game.js','public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js',
  'public/js/rng.js','public/js/vfx.js','server/sim.js',
  'public/js/main.js','public/css/style.css','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,name));
  if(provenance.inputs?.[name]!==digest(bytes))throw new Error('Source input changed; refresh shared source metadata first: '+name);
  sourceInputs[name]=digest(bytes);
}
const data=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const cast=await localCastReferences(source,data);
const defense=await localDefenseReferences(source);
const effects=await controlEffectReferences(source,data);
const fixtures={localCast:cast.fixtures,localDefense:defense.programs,localDefenseDeadlines:defense.deadlines,
  localStatus:await localStatusReferences(source),controlEffectSteps:effects.steps,controlEffectCurves:effects.curves};
for(const [name,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,name)))!==expected)throw new Error('Source changed during local controls capture: '+name);
const inputs={};
for(const name of ['tools/local_controls_capture.mjs','tools/local_cast_references.mjs','tools/local_defense_references.mjs',
  'tools/local_status_references.mjs','tools/control_effect_references.mjs'])
  inputs[name]=digest((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/local_controls.json'),{formatVersion:1,source:{inputs,sourceInputs},
  metadata:{casting:cast.timing,controlEffects:effects.rules},fixtures});
console.log('LOCAL_CONTROLS_REFERENCES_PASS '+JSON.stringify(Object.fromEntries(Object.entries(fixtures)
  .map(([key,value])=>[key,value.length]))));
