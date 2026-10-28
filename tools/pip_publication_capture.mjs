import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/pip_publication_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','server/sim.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const game=contents['public/js/game.js'],server=contents['server/sim.js'];
for(const fragment of ['ent.lost = !!e.lost;', 'if (!seen.has(id)) { this._removeEnt(id, ent, deadIds.has(id)); }',
  'this.ents.set(e.id,ent);'])
  if(!game.includes(fragment))throw new Error('Original snapshot membership contract changed: '+fragment);
if(!server.includes('if (e.lost) o.lost = 1;'))throw new Error('Original decoy loss publication changed');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const Pip=new Function('lowPower','return class {\n'+grabMethod(game,'_pipSources')+'\n};')(()=>false);
const authority=new Map(),published=new Map();
const context=Object.assign(new Pip(),{side:'STEEL',dead:false,isDrone:false,youId:17,_resScale:1,ents:published});
const steps=[];
const spawn=id=>authority.set(id,{id,pid:17,hero:false,isSelf:false,dead:false,decoy:true,lost:false,si:0});
// The source client creates and updates entries only on receipt, then removes missing IDs.
const publish=()=>{
  for(const [id,row] of authority){
    if(published.has(id))Object.assign(published.get(id),row);
    else published.set(id,{...row});
  }
  for(const id of published.keys())if(!authority.has(id))published.delete(id);
};
const record=action=>steps.push({action,authority:[...authority.values()].map(({id,lost})=>({id,lost})),
  published:[...published.values()].map(({id,lost})=>({id,lost})),selected:context._pipSources().map(row=>row.ent.id)});
publish();record('snapshot-empty');
spawn(7);record('spawn-7');
publish();record('publish-7');
authority.get(7).lost=true;record('lose-7');
publish();record('publish-lost');
authority.get(7).lost=false;record('recover-7');
publish();record('publish-recovered');
spawn(9);record('spawn-9');
publish();record('publish-two');
authority.delete(7);record('remove-7');
publish();record('publish-9');
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during PiP publication capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('PiP publication generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/pip_publication.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},steps});
console.log('PIP_PUBLICATION_REFERENCES_PASS steps='+steps.length);
