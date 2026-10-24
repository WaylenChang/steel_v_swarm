import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/dialogue.js','public/js/storytalk.js','public/js/portraits.js','public/js/lore.js',
  'public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js','public/js/rng.js','public/css/style.css']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {Dialogue}=await import(pathToFileURL(join(source,'public/js/dialogue.js')).href);
const {STORY_TALK}=await import(pathToFileURL(join(source,'public/js/storytalk.js')).href);

// Observe DOM mutations only. Text, portrait URLs, ranking and timers run original methods.
class Element {
  constructor(){
    this.children=[];this.queries=new Map();this.dataset={};this.style={display:'',setProperty(key,value){this[key]=value;}};
    this.classes=new Set();this.classList={add:name=>this.classes.add(name),toggle:(name,on)=>on?this.classes.add(name):this.classes.delete(name)};
  }
  appendChild(child){child.parent=this;this.children.push(child);}
  remove(){if(this.parent)this.parent.children=this.parent.children.filter(child=>child!==this);}
  querySelector(selector){if(!this.queries.has(selector))this.queries.set(selector,new Element());return this.queries.get(selector);}
  set innerHTML(value){this.html=value;this.children=[];this.queries.clear();}
}
const saved={document:globalThis.document,setTimeout:globalThis.setTimeout,clearTimeout:globalThis.clearTimeout};
const programs=[];
try {
  globalThis.document={createElement:()=>new Element()};
  const scenes=Object.values(STORY_TALK).flatMap(chapter=>Object.values(chapter).flatMap(side=>Object.values(side)));
  scenes.push({title:'',note:'',lines:[{ch:'s01',t:'Hostile signal'}]},
    {title:'',note:'',lines:[{ch:'t06',t:'😀😀😀😀😀'}]},
    {title:'',note:'',lines:[{ch:'t06',t:'[b]plain[/b] <tag> & "quoted"'},{ch:'s01',t:'Reply'},
      {ch:'m01',t:'Guest'},{ch:'t06',t:'Reply'},{ch:'s01',t:'Reply'},{ch:'m01',t:'Guest'}]});
  for(const scene of scenes)for(const side of ['STEEL','SWARM',''])for(const artMode of ['char','mech']) {
    let clock=0,serial=0;const tasks=new Map();
    globalThis.setTimeout=(fn,ms)=>{const id=++serial;tasks.set(id,{fn,at:clock+ms});return id;};
    globalThis.clearTimeout=id=>tasks.delete(id);
    const dialogue=new Dialogue(new Element(),{mySide:side,artMode}),frames=[];
    const snapshot=()=>{
      const bar=dialogue.bar;
      return {at:dialogue.at||0,total:dialogue.total||0,bar:!!bar,fading:!!bar?.classes.has('out'),
        text:bar?.querySelector('.dlg-line').textContent??'',speaker:bar?.querySelector('.dlg-who').textContent??'',color:bar?.style['--dlg-side']??'',
        portraits:bar?['.dlg-av-l','.dlg-av-r'].map(selector=>{
          const node=bar.querySelector(selector);
          return {id:node.dataset.ch??'',visible:node.style.display!=='none',active:node.classes.has('on'),src:node.src??''};
        }):[],timers:[...tasks.values()].map(task=>(task.at-clock)/1000).sort((a,b)=>a-b)};
    };
    dialogue.radio(scene);frames.push({action:'radio',scene,state:snapshot()});
    dialogue.radio({lines:[]});frames.push({action:'empty',state:snapshot()});
    for(let guard=0;tasks.size&&guard<100;guard++) {
      const [id,task]=[...tasks].sort((a,b)=>a[1].at-b[1].at)[0];tasks.delete(id);clock=task.at;task.fn();
      frames.push({action:'timer',state:snapshot()});
    }
    if(tasks.size)throw new Error('Original radio timers did not terminate');
    dialogue.radio(scene);frames.push({action:'radio',scene,state:snapshot()});
    const replacement=scenes.at(-1);dialogue.radio(replacement);frames.push({action:'radio',scene:replacement,state:snapshot()});
    dialogue.clear();frames.push({action:'clear',state:snapshot()});
    programs.push({side,artMode,frames});
  }
} finally {
  for(const [key,value]of Object.entries(saved)) {
    if(value===undefined)delete globalThis[key];else globalThis[key]=value;
  }
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during dialogue capture: '+file);
const file='tools/dialogue_native_capture.mjs';
const inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/dialogue_native.json'),{formatVersion:1,source:{inputs,sourceInputs},talk:STORY_TALK,programs});
console.log('DIALOGUE_NATIVE_REFERENCES_PASS programs='+programs.length);
