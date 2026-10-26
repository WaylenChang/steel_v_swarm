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
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original missile input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const data=(await readFile(join(source,'public/js/data.js'),'utf8')).replace(/\r\n?/g,'\n');
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const easing=['frictionFPS','lerpFPS'].map(name=>data.split('\n').find(line=>line.startsWith('export const '+name+' = ')));
if(easing.some(line=>!line))throw new Error('Missing original frame interpolation');
const lerpFPS=new Function(easing.map(line=>line.replace('export ','')).join('\n')+'\nreturn lerpFPS;')();
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const programs=[];
for(const terminal of ['silent','impact','wrong']) {
  const bursts=[],disposed=[],released=[];
  const scope={THREE,lerpFPS,
    // Declared geometry/damage probes isolate owner movement and retirement.
    projectileMesh:()=>new THREE.Mesh(new THREE.BoxGeometry(),new THREE.MeshBasicMaterial()),
    sceneDamageStage(){throw new Error('Health stages belong to their separate source fixtures');},
    applySceneDamage(){throw new Error('Damage geometry is outside this owner capture');},
    sceneDamageBurst(_scene,_effects,entity,stage){bursts.push({id:entity.id,stage,position:entity.mesh.position.toArray()});},
    releaseMobileDamage(entity){released.push(entity.id);},
    disposeTree(object){disposed.push(object.id);object.geometry?.dispose();object.material?.dispose();},
    stepProjectileFx(){}};
  const method=name=>new Function(...Object.keys(scope),'return ({'+grabMethod(game,name)+'})['+JSON.stringify(name)+'];')(...Object.values(scope));
  const context={scene:new THREE.Scene(),effects:[],samMeshes:new Map(),damaged:new Set(),terrain:{heightAt:()=>0}};
  const sync=method('_syncMissiles'),advance=method('_updateMissiles'),frames=[];
  for(const [point,delta]of [
    [[12,20,-9],0],[[12,20.7,-9],.06],[[12,21.5,-9],0],[[13,20,-9],.000001],
    [[13,20,-9],.016],[[14,21,-10],.1],[[15,22,-10],.06],[[15,22,-10],.4],
  ]) {
    sync.call(context,[{id:7,x:point[0],y:point[1],z:-point[2],hp:NaN,m:0}]);
    advance.call(context,delta);
    const record=context.samMeshes.get(7);
    frames.push({point,deltaBits:bits(delta),position:record.mesh.position.toArray(),quaternion:record.mesh.quaternion.toArray(),
      ageBits:bits(record.age),smokeBits:bits(record.smoke),puffs:context.effects.map(effect=>effect.obj.position.toArray())});
  }
  const events=terminal==='silent'?[]:[{e:'boom',missileId:terminal==='impact'?7:99}];
  sync.call(context,[],events);
  const first={bursts:bursts.slice(),released:released.slice(),disposed:disposed.length,count:context.samMeshes.size};
  sync.call(context,[],events);advance.call(context,.5);
  programs.push({terminal,frames,first,after:{bursts:bursts.slice(),released:released.slice(),disposed:disposed.length,
    count:context.samMeshes.size,puffs:context.effects.length}});
  for(const effect of context.effects){context.scene.remove(effect.obj);effect.obj.geometry.dispose();effect.obj.material.dispose();}
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during missile capture: '+path);
const inputs={};
for(const path of ['tools/missile_owner_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/missile_owner.json'),{formatVersion:1,source:{inputs,sourceInputs},programs});
console.log('MISSILE_OWNER_CAPTURE_PASS '+JSON.stringify({programs:programs.length}));
