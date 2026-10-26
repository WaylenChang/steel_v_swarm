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
for(const path of ['public/js/game.js','public/js/vfx.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original effect input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const vfx=(await readFile(join(source,'public/js/vfx.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const maximum=Number(/const FX_MAX = (\d+);/.exec(game)?.[1]);
if(!Number.isSafeInteger(maximum)||maximum<1)throw new Error('Missing original global effect bound');
const fadeLine=game.split('\n').find(line=>line.startsWith('function _tracerFade('));
const crowdLine=vfx.split('\n').find(line=>line.startsWith('const crowded = '));
if(!fadeLine||!crowdLine)throw new Error('Missing original effect callbacks');
const tracerFade=new Function(fadeLine+'\nreturn _tracerFade;')();
const crowded=new Function('lowPower',crowdLine+'\nreturn crowded;');
const scope={THREE,FX_MAX:maximum,_tracerFade:tracerFade,disposeTree(){throw new Error('Probe has no disposal callback');}};
const method=name=>new Function(...Object.keys(scope),'return ({'+grabMethod(game,name)+'})['+JSON.stringify(name)+'];')(...Object.values(scope));
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const cases=[];
const programs=[0,1,maximum-1,maximum,maximum+1,maximum+17].flatMap(count=>[false,true].map(invert=>({count,invert})));
programs.push({count:2,invert:false,expired:true});
for(const {count,invert,expired=false}of programs) {
  const events=[],records=[],scene=new THREE.Scene();
  // Plain record acquisition isolates insertion/update semantics, not Pool limits.
  const context={scene,effects:[],_fxShellPool:{acquire:()=>({})},_freeEffect:method('_freeEffect')};
  const append=number=>{
    const added=[];
    for(let index=0;index<number;index++) {
      const id=records.length,kind=(id%3===0)!==invert?'tracer':'combat',ttl=.1*(id%3+1);
      const obj=new THREE.Object3D();obj.material={opacity:.9};
      obj.userData.releaseFx=()=>events.push({op:'drop',id});
      scene.add(obj);
      let record;
      if(kind==='tracer') {
        method('_pushTracerFx').call(context,obj,ttl);
        record=context.effects.at(-1);
      } else {
        record={obj,ttl,age:0,dispose:obj.userData.releaseFx};
        context.effects.push(record);
      }
      const originalFade=record.fade;
      record.fade=(object,fraction,delta)=>{
        events.push({op:'fade',id,fractionBits:bits(fraction),deltaBits:bits(delta)});
        originalFade?.(object,fraction,delta);
      };
      record.id=id;record.kind=kind;records.push(record);
      const item={id,kind,ttlBits:bits(ttl)};
      // Directed pre-aged records isolate zero-delta expiry from construction.
      if(expired&&id<count) {
        record.ttl=id===0?0:-.02;record.age=ttl-record.ttl;
        item.durationBits=bits(ttl);item.ttlBits=bits(record.ttl);item.ageBits=bits(record.age);
      }
      added.push(item);
    }
    return added;
  };
  const initial=append(count),frames=[];
  for(const [delta,extra]of [[0,0],[.05,0],[.05,23],[0,maximum+3],[.2,0],[0,0]]) {
    const added=append(extra);events.length=0;
    method('_updateEffects').call(context,delta);
    frames.push({deltaBits:bits(delta),added,events:[...events],remaining:context.effects.map(record=>({id:record.id,
      ttlBits:bits(record.ttl),ageBits:bits(record.age),opacity:record.kind==='tracer'?record.obj.material.opacity:null}))});
  }
  cases.push({count,invert,expired,initial,frames});
  scene.clear();
}
const crowd=[];
for(const low of [false,true])for(let count=0;count<=maximum+1;count++)
  crowd.push({low,count,result:crowded(()=>low)({length:count})});
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during effect capture: '+path);
const inputs={};
for(const path of ['tools/effect_order_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'data/presentation_effect_order.json'),{formatVersion:1,source:{inputs,sourceInputs},maximum,cases,crowd});
console.log('EFFECT_ORDER_CAPTURE_PASS '+JSON.stringify({maximum,cases:cases.length,frames:cases.reduce((sum,item)=>sum+item.frames.length,0)}));
