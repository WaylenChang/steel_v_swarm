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
for(const path of ['public/js/game.js','public/js/data.js','public/js/hazards.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original collectible input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const original=async path=>(await readFile(join(source,path),'utf8')).replace(/\r\n?/g,'\n');
const game=await original('public/js/game.js'),data=await original('public/js/data.js'),hazards=await original('public/js/hazards.js');
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const {grabFn,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const constant=(text,name)=>new Function(text.match(new RegExp('(?:export )?const '+name+' = \\{[\\s\\S]*?\\n\\};'))?.[0].replace('export ','')+'\nreturn '+name+';')();
const AIRDROP=constant(data,'AIRDROP'),AIRDROP_TONE=constant(hazards,'AIRDROP_TONE'),FIRE_WEATHER=constant(data,'FIRE_WEATHER');
const fireDotMul=new Function('FIRE_WEATHER','return '+grabFn(data,'fireDotMul'))(FIRE_WEATHER);
const geometry=()=>new THREE.BufferGeometry();
// Actual constructors retain their hierarchy/poses. Only geometry and toon/outline rendering are probes.
const mesh=(parent,shape,color,x=0,y=0,z=0,options={})=>{
  const material=new THREE.MeshBasicMaterial({color});
  for(const key of ['transparent','opacity','depthWrite','side','blending'])if(key in options)material[key]=options[key];
  const node=new THREE.Mesh(shape,material);node.position.set(x,y,z);parent.add(node);return node;
};
const constructors={THREE,AIRDROP_TONE,furnitureSceneGeometry:geometry,scenePartGeometry:geometry,
  box:geometry,cyl:geometry,cone:geometry,ico:geometry,mesh,
  addSceneGeometry:(parent,shape)=>mesh(parent,shape,0xffffff),outlinify(){}};
const build=name=>new Function(...Object.keys(constructors),'return '+grabFn(hazards,name))(...Object.values(constructors));
const originalDrop=build('buildAirdrop'),originalLoot=build('buildLoot');
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const programs=[];
for(const size of ['S','M','L'])for(const landing of [false,true])for(const kind of ['cash','ammo','affix']) {
  let wall=5,created=0;const roots=[],admissions=[];
  const admit=object=>{created++;roots.push(object);object.addEventListener('added',()=>admissions.push(object.position.toArray()));return object;};
  const scope={THREE,AIRDROP,performance:{now:()=>wall*1000},buildAirdrop:key=>admit(originalDrop(key)),
    buildLoot:(ammo,affix)=>admit(originalLoot(ammo,affix)),fireDotMul,
    stepFireVisual(){throw new Error('Collectible capture cannot substitute fire animation');}};
  const method=name=>new Function(...Object.keys(scope),'return ({'+grabMethod(game,name)+'})['+JSON.stringify(name)+'];')(...Object.values(scope));
  const context={scene:new THREE.Scene(),terrain:{heightAt:()=>7},airdropMeshes:new Map(),lootMeshes:new Map(),flamers:[]};
  const snapshot=()=>{
    const drop=context.airdropMeshes.get(1),loot=context.lootMeshes.get(2),u=drop?.userData;
    return {created,admissions:admissions.slice(),children:context.scene.children.length,
      drop:drop?{position:drop.position.toArray(),bornBits:bits(u.bornT),landing:u.landing,
        rootYawBits:bits(drop.rotation.y),crateYawBits:bits(u.crate.rotation.y),crateY:u.crate.position.y,
        chute:u.chute.visible,groundChute:u.groundChute.visible,halo:u.halo.visible}:null,
      loot:loot?{position:loot.position.toArray(),yawBits:bits(loot.rotation.y),bodyY:loot.children[0].position.y}:null};
  };
  const frames=[];
  for(const [at,delta,present,replace]of [[5,0,true,false],[5.1,.1,true,true],[7,.2,true,true],[7.1,0,false,false],
    [9,0,true,false],[9.2,.2,true,true],[10,0,false,false],[10.1,0,false,false]]) {
    wall=at;
    const point=replace?[99,7,-88]:[12,7,-8];
    const drop=present?[{id:1,x:point[0],z:-point[2],s:replace?'L':size,d:replace?!landing:landing}]:[];
    const loot=present?[{id:2,x:point[0],z:-point[2],a:replace?kind!=='ammo':kind==='ammo',f:replace?kind!=='affix':kind==='affix'}]:[];
    method('_syncAirdrop').call(context,drop);method('_syncLoot').call(context,loot);
    method('_updateAirdrop').call(context,delta,wall);method('_updateLoot').call(context,delta,wall);
    frames.push({wallBits:bits(wall),deltaBits:bits(delta),present,replace,point,result:snapshot()});
  }
  programs.push({size,landing,kind,frames});
  const materials=new Set(),geometries=new Set();
  for(const object of roots)object.traverse(node=>{if(node.geometry)geometries.add(node.geometry);if(node.material)materials.add(node.material);});
  for(const value of geometries)value.dispose();for(const value of materials)value.dispose();
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during collectible capture: '+path);
const inputs={};
for(const path of ['tools/collectible_owner_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/collectible_owner.json'),{formatVersion:1,source:{inputs,sourceInputs},
  rules:{landing:AIRDROP.LAND_S,height:AIRDROP.DROP_H},programs});
console.log('COLLECTIBLE_OWNER_CAPTURE_PASS '+JSON.stringify({programs:programs.length}));
