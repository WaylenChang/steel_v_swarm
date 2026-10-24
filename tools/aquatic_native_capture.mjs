import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {aquaticReferences} from './aquatic_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/aquatics.js','public/js/vesselCatalog.js','public/js/biomes.js','public/js/toon.js',
  'public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js','public/js/rng.js',
  'out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const fixtures=await aquaticReferences(source,{extraTimes:[100000.12345,100001.333333333,1000000.12345]});
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during aquatic capture: '+file);
const inputs={};
for(const file of ['tools/aquatic_native_capture.mjs','tools/aquatic_references.mjs',
  'tools/aquatic_capture.mjs','tools/scenery_motion_capture.mjs','tools/marine_references.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/aquatic_native.json'),{formatVersion:1,source:{inputs,sourceInputs},...fixtures});
console.log('AQUATIC_NATIVE_REFERENCES_PASS programs='+fixtures.aquaticPrograms.length);
