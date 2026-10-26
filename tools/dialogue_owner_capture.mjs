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
for(const path of ['public/js/dialogue.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original dialogue input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const text=(await readFile(join(source,'public/js/dialogue.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const methods=['_after','clear','dispose'].map(name=>grabMethod(text,name)).join('\n');
const programs=[];
// Timer/DOM probes isolate cancellation, without importing unrelated data or RNG modules.
for(const cancellation of ['clear','dispose'])for(const firstDelivery of [false,true]) {
  let now=0,serial=0;
  const tasks=new Map(),delivered=[],frames=[];
  const Original=new Function('setTimeout','clearTimeout','return class Original {'+methods+'}')(
    (fn,delay)=>{tasks.set(++serial,{fn,deadline:now+delay});return serial;},id=>tasks.delete(id));
  const original=new Original();
  original.timers=new Set();original.root={innerHTML:''};original.bar=null;original.at=0;original.total=0;
  const actions=[{action:'schedule',delay:180,id:'row'}, {action:'schedule',delay:1700,id:'line'}];
  if(firstDelivery)actions.push({action:'deliver'});
  actions.push({action:cancellation},{action:'schedule',delay:420,id:'replacement'},{action:'deliver'},{action:cancellation});
  for(const action of actions) {
    if(action.action==='schedule')original._after(action.delay,()=>delivered.push(action.id));
    else if(action.action==='deliver') {
      const [id,task]=[...tasks].sort((a,b)=>a[1].deadline-b[1].deadline)[0];
      tasks.delete(id);now=task.deadline;task.fn();
    } else original[action.action]();
    frames.push({...action,now,delivered:delivered.slice(),timers:[...tasks.values()].map(task=>task.deadline-now)});
  }
  programs.push({cancellation,firstDelivery,frames});
}
for(const [path,hash]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Source changed during dialogue capture: '+path);
const inputs={};
for(const path of ['tools/dialogue_owner_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/dialogue_owner.json'),{formatVersion:1,source:{inputs,sourceInputs},programs});
console.log('DIALOGUE_OWNER_CAPTURE_PASS programs='+programs.length);
