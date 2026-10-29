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
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/css/style.css','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const {CHAPTER_SCENES}=await import(pathToFileURL(join(source,'public/js/chapterScenes.js')).href);
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const markerStyle=css.match(/\.pcs-chapter-mark\s*\{([^}]*)\}/)?.[1];
const gap=markerStyle?.match(/\bgap\s*:\s*([\d.]+)px\s*;/)?.[1];
if(gap===undefined)throw new Error('Missing original cinematic section-marker gap');
globalThis.document={getElementById:()=>({addEventListener(){}})};
const programs=[];let prefix;
for(const [kind,scenes] of [['prologue',PROLOGUE_SCENES],['steel',CHAPTER_SCENES.ch1.STEEL],['swarm',CHAPTER_SCENES.ch1.SWARM]]){
  const content={innerHTML:''};
  const controller=Object.assign(Object.create(PrologueIntroController.prototype),{
    scenes,scenesContainer:null,content,isPrologue:kind==='prologue',options:{},bindEvents(){}});
  controller.initDOM();
  const matches=[...content.innerHTML.matchAll(/<span class="pcs-badge">([^<]*)<\/span>\s*<span class="pcs-title-inline">([^<]*)<\/span>/g)];
  if(matches.length!==scenes.length)throw new Error('Original section marker count changed: '+kind);
  const markers=matches.map((match,index)=>{
    const scene=scenes[index];
    if(match[1]!==scene.badge||!match[2].endsWith(scene.title))throw new Error('Original section marker text changed: '+scene.id);
    const candidate=match[2].slice(0,match[2].length-scene.title.length);
    if(prefix!==undefined&&candidate!==prefix)throw new Error('Original section marker prefix varies');
    prefix=candidate;
    return {id:scene.id,badge:match[1],title:match[2]};
  });
  programs.push({kind,markers});
}
if(!prefix)throw new Error('Missing original section marker prefix');
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_section_marker_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules:{prefix,gap:Number(gap)}};
await writeFixtureJson(join(root,'data/campaign_section_marker.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_section_marker.json'),{...base,programs});
console.log('CAMPAIGN_SECTION_MARKER_CAPTURE_PASS programs='+programs.length);
