import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {wildlifeReferences} from './wildlife_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/biomes.js','public/js/wildlife.js','public/js/wildlifeRender.js',
  'public/js/ambientMeshData.js','public/js/ground.js','public/js/lod.js','public/js/weatherVisuals.js',
  'public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js','public/js/rng.js',
  'out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const fixtures=await wildlifeReferences(source);
for(const initialActivity of [0,.15,.5]) {
  const constructors=await wildlifeReferences(source,{initialActivity,modes:['split'],selections:['all','stress','no_anchors']});
  fixtures.wildlifePrograms.push(...constructors.wildlifePrograms);
  fixtures.wildlifeDensityPrograms.push(...constructors.wildlifeDensityPrograms);
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during wildlife capture: '+file);
const inputs={};
for(const file of ['tools/wildlife_native_capture.mjs','tools/wildlife_references.mjs',
  'tools/wildlife_capture.mjs','tools/wildlife_density_references.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/wildlife_native.json'),{formatVersion:1,source:{inputs,sourceInputs},...fixtures});
console.log('WILDLIFE_NATIVE_REFERENCES_PASS '+JSON.stringify({programs:fixtures.wildlifePrograms.length,
  densities:fixtures.wildlifeDensityPrograms.length,activity:fixtures.wildlifeActivity.length}));
