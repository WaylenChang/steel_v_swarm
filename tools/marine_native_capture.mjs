import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {marineReferences} from './marine_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
// The original extracted scan/hash/packet programs execute no source module initializers or RNG.
for(const file of ['public/js/toon.js','public/js/game.js','tools/audit_src.mjs','out/forest_review/three.module.js']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs[file]!==digest(bytes))throw new Error('Original marine program input changed: '+file);
  sourceInputs[file]=digest(bytes);
}
const fixtures=await marineReferences(source);
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during marine capture: '+file);
const inputs={};
for(const file of ['tools/marine_native_capture.mjs','tools/marine_references.mjs','tools/fixture_json.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/marine_native.json'),{formatVersion:1,source:{inputs,sourceInputs},...fixtures});
console.log('MARINE_NATIVE_CAPTURE_PASS '+JSON.stringify({programs:fixtures.marineRipplePrograms.length}));
