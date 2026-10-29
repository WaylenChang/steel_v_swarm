import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const scenes=PROLOGUE_SCENES.map(({id,tag,badge,title})=>({id,tag,badge,title}));
const items=scenes.map(()=>({classList:{active:false,toggle(_name,value){this.active=value;}}}));
const sections=scenes.map(()=>({classList:{active:false,toggle(_name,value){this.active=value;}}}));
globalThis.document={getElementById:()=>null};
const context=Object.assign(Object.create(PrologueIntroController.prototype),{
  scenes,activeSceneIdx:-1,dateTagEl:{textContent:''},badgeEl:{textContent:''},titleEl:{textContent:''},
  root:{querySelectorAll:()=>items},content:{querySelectorAll:()=>sections}});
const frames=[];
for(const index of [0,2,4,4,-1,scenes.length,1]){
  context.setScene(index);
  frames.push({index,active:context.activeSceneIdx,tag:context.dateTagEl.textContent,badge:context.badgeEl.textContent,
    title:context.titleEl.textContent,activeItems:items.map(item=>item.classList.active),
    activeSections:sections.map(section=>section.classList.active)});
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_heading_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_heading.json'),{formatVersion:1,source:{inputs,sourceInputs},scenes,frames});
console.log('CAMPAIGN_HEADING_CAPTURE_PASS frames='+frames.length);
