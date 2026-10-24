import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {visualReferences} from './visual_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/visualPrefs.js','public/js/toon.js','public/js/biomes.js',
  'out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Source changed; refresh shared metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const captured=await visualReferences(source);
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during visual capture: '+file);
const inputs={};
for(const file of ['tools/visual_preferences_capture.mjs','tools/visual_references.mjs','tools/marine_visual_references.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/visual_preferences.json'),{formatVersion:1,source:{inputs,sourceInputs},
  metadata:captured.rules,fixtures:captured.fixtures});
console.log('VISUAL_PREFERENCES_REFERENCES_PASS '+JSON.stringify(Object.fromEntries(Object.entries(captured.fixtures)
  .map(([key,value])=>[key,value.length]))));
