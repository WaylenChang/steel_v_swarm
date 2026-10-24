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
for(const file of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const saved=Object.fromEntries(['window','performance','requestAnimationFrame','cancelAnimationFrame','setTimeout']
  .map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]));
class Target {
  constructor(){this.events=new Map();this.classList={add(){},remove(){}};this.style={};}
  addEventListener(name,callback){this.events.set(name,callback);}
  emit(name,event){this.events.get(name)?.(event);}
}
const programs=[];
const cases=[
  [{type:'down',time:1000},{type:'cancel',time:1100},{type:'down',time:1200},{type:'up',time:1300}],
  [{type:'down',time:1000},{type:'cancel',time:1100},{type:'raf',time:2000}],
  [{type:'down',time:1000},{type:'up',time:1010},{type:'down',time:1200},{type:'up',time:1359.999}],
  [{type:'down',time:1000},{type:'up',time:1010},{type:'down',time:1200},{type:'up',time:1360}],
  [{type:'down',time:1000},{type:'raf',time:1649.999},{type:'raf',time:1650}],
  [{type:'down',time:1000,button:true},{type:'raf',time:2000},{type:'up',time:2010}],
  [{type:'down',time:1000,button:true},{type:'up',time:1010},{type:'down',time:1100},{type:'up',time:1200}],
  [{type:'up',time:1000},{type:'down',time:1100},{type:'up',time:1200}],
  [{type:'down',time:0},{type:'up',time:10}],
  [{type:'down',time:1000,scroll:true},{type:'up',time:1500,scroll:true},{type:'wheel',time:2000,scroll:true}],
  [{type:'down',time:1000,scroll:true},{type:'drag',time:1200,scroll:true},{type:'cancel',time:1300,scroll:true}],
  [{type:'mouse_down',time:1000,button:true},{type:'raf',time:2000},{type:'mouse_up',time:2010}],
  [{type:'mouse_down',time:1000},{type:'raf',time:1650}],
  [{type:'double_click',time:1000}],
];
try {
  for(const operations of cases) {
    let now=0,serial=0;const rafs=new Map(),touches=new Map(),window=new Target();
    Object.assign(window,{innerWidth:1024,innerHeight:768});
    for(const [key,value]of Object.entries({window,performance:{now:()=>now},requestAnimationFrame:callback=>{
      const id=++serial;rafs.set(id,callback);return id;},cancelAnimationFrame:id=>rafs.delete(id),setTimeout:()=>++serial}))
      Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
    const context=Object.assign(Object.create(PrologueIntroController.prototype),{root:new Target(),viewport:new Target(),
      holdIndicator:null,holdCircle:null,holdRaf:null,holdStart:0,lastTapTime:0,userScrollPauseUntil:0,
      destroyed:false,isBufferComplete:true,isPrologue:false,options:{}});
    context.bindEvents();
    const frames=[];
    for(const operation of operations) {
      now=operation.time;
      const event=button=>({target:{closest:()=>button},preventDefault(){},clientX:100,clientY:100});
      const id=operation.id??0;
      switch(operation.type) {
        case 'down':touches.set(id,!!operation.button);context.root.emit('pointerdown',event(!!operation.button));
          if(operation.scroll)context.viewport.emit('touchstart',event(false));break;
        case 'up':case 'cancel': {
          const paired=touches.has(id),button=touches.get(id);touches.delete(id);
          window.emit(operation.type==='cancel'?'pointercancel':'pointerup',event(button));
          if(operation.type==='up'&&paired)context.root.emit('touchend',event(button));break;
        }
        case 'drag':if(operation.scroll)context.viewport.emit('touchmove',event(false));break;
        case 'wheel':context.viewport.emit('wheel',event(false));break;
        case 'mouse_down':context.root.emit('pointerdown',event(!!operation.button));break;
        case 'mouse_up':window.emit('pointerup',event(!!operation.button));break;
        case 'double_click':context.root.emit('dblclick',event(false));break;
        case 'raf': {
          const pending=[...rafs];rafs.clear();for(const [,callback]of pending)callback(now);break;
        }
      }
      frames.push({operation,state:{closing:context.destroyed,holding:context.holdRaf!==null,
        pausedUntil:context.userScrollPauseUntil,lastTap:context.lastTapTime}});
      if(context.destroyed)break;
    }
    programs.push({frames});
  }
} finally {
  for(const [key,descriptor]of Object.entries(saved)) {
    if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];
  }
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during cinematic input capture: '+file);
const file='tools/campaign_input_capture.mjs';
const inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/campaign_input.json'),{formatVersion:1,source:{inputs,sourceInputs},programs});
console.log('CAMPAIGN_INPUT_REFERENCES_PASS programs='+programs.length);
