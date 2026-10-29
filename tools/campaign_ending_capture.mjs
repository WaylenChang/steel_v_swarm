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
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/js/main.js','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const main=await readFile(join(source,'public/js/main.js'),'utf8');
const chapterButtons=main.match(/finishBtnText:\s*onDone\s*\?\s*'([^']+)'\s*:\s*'([^']+)'/);
if(!chapterButtons)throw new Error('Missing original chapter briefing finish labels');
globalThis.document={getElementById:()=>({addEventListener(){}})};
const cases=[];
for(const [kind,finishText] of [['prologue',null],['prologue','custom'],['chapter',null],['chapter',''],['chapter',chapterButtons[1]],['chapter',chapterButtons[2]]]){
  const content={innerHTML:''};
  const controller=Object.assign(Object.create(PrologueIntroController.prototype),{
    scenes:PROLOGUE_SCENES.slice(0,1),scenesContainer:null,content,isPrologue:kind==='prologue',
    options:finishText===null?{}:{finishBtnText:finishText},bindEvents(){}});
  controller.initDOM();
  const match=(pattern,label)=>{
    const value=content.innerHTML.match(pattern)?.[1]?.trim();
    if(!value)throw new Error('Missing original cinematic '+label);
    return value;
  };
  cases.push({kind,finishText,divider:match(/<div class="pce-divider">([^<]+)<\/div>/,'divider'),
    note:match(/<p class="pce-note">([^<]+)<\/p>/,'end note'),
    button:match(/<button id="prologueFinishBtn"[^>]*>\s*([^<]+)<\/button>/,'finish button')});
}
const first=cases[0],chapter=cases[2];
if(cases.some(row=>row.divider!==first.divider))throw new Error('Original cinematic divider varies');
const rules={divider:first.divider,prologue:{note:first.note,button:first.button},chapter:{note:chapter.note,button:chapter.button}};
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_ending_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_ending.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_ending.json'),{...base,cases});
console.log('CAMPAIGN_ENDING_CAPTURE_PASS cases='+cases.length);
