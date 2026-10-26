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
for(const path of ['public/js/mobile.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original touch input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const mobile=(await readFile(join(source,'public/js/mobile.js'),'utf8')).replace(/\r\n?/g,'\n');
const text=mobile.slice(mobile.indexOf('export class TouchControls'));
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const rules=new Function(grabConst(mobile,'LOOK')+';return LOOK;')();
const OriginalReset=new Function('document','return class OriginalReset {'+['reset','_setLookFire'].map(name=>grabMethod(text,name)).join('\n')+'}')(
  {querySelectorAll:()=>[]});
const cases=[];
for(const lookFire of [false,true])for(const held of [[],['fire'],['fire','fire'],['jump','aim','dive','lock']])for(const blocked of [false,true]) {
  const events=[];
  const original=new OriginalReset();
  Object.assign(original,{axis:{f:1,r:-1,mag:1},_lookId:1,_lookFire:lookFire,_fireArm:true,_tapAt:1000,
    moveStick:{id:2,x:1,y:-1,mag:1},lookStick:{id:3,x:-1,y:1,mag:1},
    _held:new Map(held.map((action,index)=>[index+4,action])),_tap:new Map([[9,{action:'reload'}]]),
    _blocked:()=>blocked,_stickPaint(){},_haptic:milliseconds=>events.push({type:'haptic',milliseconds}),
    client:{_cmd:(action,on)=>events.push({type:'command',action,on})}});
  original.reset();
  cases.push({initial:{lookFire,held,blocked},events,cleared:original._held.size===0&&original._tap.size===0
    &&original._lookId===null&&!original._lookFire&&!original._fireArm&&original._tapAt===0
    &&[original.moveStick,original.lookStick].every(stick=>stick.id===null&&stick.mag===0)
    &&original.axis.f===0&&original.axis.r===0&&original.axis.mag===0});
}
for(const [path,hash]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Source changed during touch capture: '+path);
const inputs={};
for(const path of ['tools/touch_reset_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/touch_reset.json'),{formatVersion:1,source:{inputs,sourceInputs},rules,cases});
console.log('TOUCH_RESET_CAPTURE_PASS '+JSON.stringify({cases:cases.length}));
