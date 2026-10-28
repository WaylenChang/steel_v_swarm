import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/campaign_hold_warning_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const keys=['window','performance','requestAnimationFrame','cancelAnimationFrame','setTimeout','localStorage'];
const saved=Object.fromEntries(keys.map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]));
const classes=()=>{
  const items=new Set();
  return {add(...names){names.forEach(name=>items.add(name));},remove(...names){names.forEach(name=>items.delete(name));},
    contains:name=>items.has(name)};
};
const element=()=>({classList:classes(),style:{},innerHTML:''});
const operations=[
  {type:'down',time:1000},{type:'frame',time:1649.999},{type:'frame',time:1650},
  {type:'frame',time:1700},{type:'down',time:1800},{type:'frame',time:2450},
  {type:'up',time:2460},{type:'down',time:2600},{type:'ready',time:2700},
  {type:'frame',time:3249.999},{type:'frame',time:3250}
];
let now=0,serial=0;const rafs=new Map(),timeouts=[];
const values={window:{innerWidth:1024,innerHeight:768},performance:{now:()=>now},
  requestAnimationFrame:callback=>{const id=++serial;rafs.set(id,callback);return id;},
  cancelAnimationFrame:id=>rafs.delete(id),setTimeout:(callback,delay)=>{timeouts.push({callback,delay});return ++serial;},
  localStorage:{setItem(){}}};
const frames=[];
try{
  for(const [key,value] of Object.entries(values))Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
  const context=Object.assign(Object.create(PrologueIntroController.prototype),{root:element(),statusEl:element(),skipHintEl:element(),
    holdIndicator:element(),holdCircle:element(),holdRaf:null,holdStart:0,animRaf:null,
    bufferPercent:37,isBufferComplete:false,isPrologue:true,destroyed:false,options:{}});
  context.renderStatus();
  for(const operation of operations){
    now=operation.time;
    if(operation.type==='down')context.startLongPress({clientX:100,clientY:100});
    else if(operation.type==='up')context.cancelLongPress();
    else if(operation.type==='ready'){context.isBufferComplete=true;context.bufferPercent=100;context.renderStatus();}
    else if(operation.type==='frame'){
      const callbacks=[...rafs.values()];rafs.clear();for(const callback of callbacks)callback(now);
    }
    frames.push({operation,active:context.holdIndicator.classList.contains('active'),holding:context.holdRaf!==null,
      offset:Number(context.holdCircle.style.strokeDashoffset),ready:context.isBufferComplete,destroyed:context.destroyed,
      warnings:timeouts.filter(timer=>timer.delay===1800).length,
      status:context.statusEl.innerHTML.replace(/<[^>]*>/g,'')});
  }
}finally{
  for(const [key,descriptor] of Object.entries(saved)){
    if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];
  }
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during campaign hold capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Campaign hold warning generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/campaign_hold_warning.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},frames});
console.log('CAMPAIGN_HOLD_WARNING_REFERENCES_PASS frames='+frames.length);
