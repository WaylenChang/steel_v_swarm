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
for(const path of ['public/js/mobile.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original gyro input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const text=(await readFile(join(source,'public/js/mobile.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const LOOK=new Function(grabConst(text,'LOOK')+';return LOOK;')();
const TOUCH=new Function(grabConst(text,'TOUCH')+';return TOUCH;')();
const gyro=text.slice(text.indexOf('\nclass Gyro {'),text.indexOf('/* ---------------- 現役實例'));
const code='return class OriginalGyro {'+['constructor','start','stop','_use','_unbind','_readMotion','_emit'].map(name=>grabMethod(gyro,name)).join('\n')+'}';
const programs=[];
for(const sourcePath of ['motion','orient','auto']) {
  const events=new Map(),timers=new Map(),outputs=[],failures=[];let timer=0;
  const target=prefix=>({addEventListener:(name,fn)=>events.set(prefix+name,fn),removeEventListener:(name,fn)=>{
    if(events.get(prefix+name)===fn)events.delete(prefix+name);
  }});
  const window={...target('window:'),screen:{orientation:target('screen:')},DeviceMotionEvent:class {}};
  const OriginalGyro=new Function('THREE','LOOK','TOUCH','window','clearTimeout','setTimeout','performance','screenAngle','clamp',code)(
    THREE,LOOK,{...TOUCH,gyroSrc:sourcePath},window,id=>timers.delete(id),(fn)=>{timers.set(++timer,fn);return timer;},
    {now:()=>1000},()=>0,(value,min,max)=>Math.max(min,Math.min(max,value)));
  const original=new OriginalGyro((x,y)=>outputs.push([x,y]),reason=>failures.push(reason));
  const steps=[];
  for(const action of ['start','sample','sample','stop','sample','stop','start','sample','sample','stop']) {
    outputs.length=0;failures.length=0;
    if(action==='sample')original._readMotion({rotationRate:{alpha:0,beta:30,gamma:-20},interval:16});
    else original[action]();
    steps.push({action,active:original.active,have:original._have,events:original.events,usable:original.usable,
      listeners:[...events.keys()].sort(),timers:timers.size,outputs:outputs.slice(),failures:failures.slice(),
      accumulated:[original.accYaw*Math.PI/180,original.accPitch*Math.PI/180]});
  }
  programs.push({source:sourcePath,steps});
}
for(const [path,hash]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Source changed during gyro capture: '+path);
const inputs={};
for(const path of ['tools/gyro_owner_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/gyro_owner.json'),{formatVersion:1,source:{inputs,sourceInputs},rules:LOOK,programs});
console.log('GYRO_OWNER_CAPTURE_PASS '+JSON.stringify({programs:programs.length,steps:programs.reduce((sum,item)=>sum+item.steps.length,0)}));
