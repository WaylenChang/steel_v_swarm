import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';
import {projectileReferences} from './projectile_references.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original projectile input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const data=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const poolMax=Number(/const PROJ_POOL_MAX = (\d+);/.exec(game)?.[1]);
if(!Number.isSafeInteger(poolMax)||poolMax<1)throw new Error('Missing original projectile pool bound');
let created=0,disposed=0,released=0;
const scope={THREE,CHARACTERS:data.CHARACTERS,sideInfo:data.sideInfo,_shotColCache:new Map(),PROJ_POOL_MAX:poolMax,
  // Geometry is a declared probe; the original methods own every pool decision.
  projectileMesh:()=>{const mesh=new THREE.Object3D();mesh.userData.probe=created++;return mesh;},
  disposeTree:()=>disposed++};
const method=name=>new Function(...Object.keys(scope),'return ({'+grabMethod(game,name)+'})['+JSON.stringify(name)+'];')(...Object.values(scope));
const client={scene:new THREE.Scene(),_projPool:new Map(),side:'STEEL',ch:'t06',_shotCols:method('_shotCols'),
  _recPool:{release(record){if(record.mesh!==null)throw new Error('Source record still owns its recycled mesh');released++;}}};
const take=method('_takeProjectile'),drop=method('_dropBullet');
const definition=data.heroWeapon('t06','light',1);
const records=[];
for(let index=0;index<poolMax+1;index++) {
  const mesh=take.call(client,definition,false);client.scene.add(mesh);
  records.push({mesh});
}
const steps=[];
for(let index=records.length-1;index>=0;index--) {
  drop.call(client,records[index]);
  steps.push({index,cleared:records[index].mesh===null,free:[...client._projPool.values()][0].length,disposed,released});
}
const next=take.call(client,definition,false);
next.scale.set(2,3,4);client.scene.add(next);drop.call(client,{mesh:next});
const reused=take.call(client,definition,false);
const reuse={index:reused.userData.probe,scale:reused.scale.toArray(),visible:reused.visible,created};
// The supplied line isolates original vertex/material writes, not Pool capacity.
const tracerGeometry=new THREE.BufferGeometry();
tracerGeometry.setAttribute('position',new THREE.BufferAttribute(new Float32Array(6),3));
const tracerMaterial=new THREE.LineBasicMaterial({transparent:true});
const tracerLine=new THREE.Line(tracerGeometry,tracerMaterial);
const tracerClient={scene:new THREE.Scene(),_tracerPool:{acquire:()=>tracerLine},_pushTracerFx(){}};
const tracer=method('_tracer'),tracerUpdates=[];
for(const [start,end,color,ttl]of [
  [[1,2,3],[-4,5,-6],0x4fc3f7,.1],
  [[-8,7,-6],[5,-4,3],0xffb300,.35],
  [[100000001,.125,-.375],[100000009,3.25,.625],0xffffff,.2],
]) {
  tracer.call(tracerClient,new THREE.Vector3(...start),new THREE.Vector3(...end),color,ttl);
  tracerUpdates.push({start,end,color,ttl,vertices:[...tracerGeometry.attributes.position.array],
    opacity:tracerMaterial.opacity,geometrySame:tracerLine.geometry===tracerGeometry,materialSame:tracerLine.material===tracerMaterial});
}
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const fade=game.split('\n').find(line=>line.startsWith('function _tracerFade('));
if(!fade)throw new Error('Missing original tracer fade');
scope.FX_MAX=Number(/const FX_MAX = (\d+);/.exec(game)?.[1]);
if(!Number.isSafeInteger(scope.FX_MAX))throw new Error('Missing original effect bound');
const tracerFade=new Function(fade+'\nreturn _tracerFade;')();
const tracerSequences=[];
for(const ttl of [.1,.35]) {
  const context={scene:new THREE.Scene(),effects:[],_tracerPool:{acquire:()=>tracerLine},
    _pushTracerFx(line,duration){this.effects.push({obj:line,ttl:duration,age:0,fade:tracerFade,dispose:()=>{line.visible=false;}});},
    _freeEffect:method('_freeEffect')};
  tracer.call(context,new THREE.Vector3(1,2,3),new THREE.Vector3(-4,5,-6),0xffffff,ttl);
  const record=context.effects[0],frames=[];
  for(const delta of [0,.001,1/60,.017,.032,.04,.06,.09,.15,.2]) {
    method('_updateEffects').call(context,delta);
    frames.push({deltaBits:bits(delta),ttlBits:bits(record.ttl),ageBits:bits(record.age),
      active:context.effects.length>0,visible:tracerLine.visible,opacity:tracerMaterial.opacity});
  }
  tracerSequences.push({ttlBits:bits(ttl),frames});
}
tracerGeometry.dispose();tracerMaterial.dispose();
const captured=await projectileReferences(data,game,source);
const flight=captured.visualShells.filter(item=>item.character===definition.ch&&item.slot===definition.slot&&item.level===1);
if(flight.length!==4)throw new Error('Missing original ordinary/hit/range visual flight programs');
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during projectile capture: '+path);
const inputs={};
for(const path of ['tools/projectile_owner_capture.mjs','tools/projectile_references.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'data/projectile_presentation.json'),{formatVersion:1,source:{inputs,sourceInputs},
  poolMax,key:[definition.ch,definition.slot,'steel'].join('-'),steps,reuse,flight,tracerFrames:captured.tracerPresentation,tracerUpdates,tracerSequences});
console.log('PROJECTILE_OWNER_CAPTURE_PASS '+JSON.stringify({poolMax,created,disposed,steps:steps.length}));
