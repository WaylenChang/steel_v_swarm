import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/game.js','public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js',
  'public/js/rng.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Source changed; refresh shared metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const d=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
let wall=0;
// These doubles supply only fields mutated by the original clock methods; native tests load real packed scenes.
const buildAirdrop=()=>{
  const group=new THREE.Group();
  for(const key of ['crate','chute','groundChute','halo']) {
    const node=new THREE.Group();group.add(node);group.userData[key]=node;
  }
  return group;
};
const buildLoot=()=>{const group=new THREE.Group();group.add(new THREE.Group());return group;};
const scope={THREE,AIRDROP:d.AIRDROP,performance:{now:()=>wall*1000},buildAirdrop,buildLoot,
  fireDotMul:d.fireDotMul,stepFireVisual:()=>{throw new Error('Clock fixture must not substitute fire visuals');}};
const method=name=>new Function(...Object.keys(scope),'return ({'+grabMethod(game,name)+'})['+JSON.stringify(name)+'];')(...Object.values(scope));
const syncAirdrop=method('_syncAirdrop'),updateAirdrop=method('_updateAirdrop');
const syncLoot=method('_syncLoot'),updateLoot=method('_updateLoot');
const programs=[];
for(const born of [0,5])for(const landing of [false,true])for(const size of ['S','M','L']) {
  const client={scene:new THREE.Scene(),terrain:{heightAt:()=>7},airdropMeshes:new Map(),lootMeshes:new Map(),flamers:[]};
  const steps=[];
  const record=input=>{
    const drop=client.airdropMeshes.get(1),loot=client.lootMeshes.get(2),u=drop.userData;
    steps.push({...input,deltaBits:bits(input.delta),drop:{y:drop.position.y,yaw:drop.rotation.y,yawBits:bits(drop.rotation.y),rotation:drop.quaternion.toArray(),born:u.bornT,
      crateYaw:u.crate.rotation.y,crateY:(!u.landing||!u.chute.visible)?u.crate.position.y:null,
      crateYawBits:bits(u.crate.rotation.y),crateRotation:u.crate.quaternion.toArray(),
      chute:u.chute.visible,groundChute:u.groundChute.visible,halo:u.halo.visible},
      loot:{yaw:loot.rotation.y,yawBits:bits(loot.rotation.y),rotation:loot.quaternion.toArray(),y:loot.children[0].position.y}});
  };
  for(const [offset,delta,authority,sync]of [[0,0,100,true],[.016,.016,100,false],[.4,.05,99,true],
    [1.1,.05,300,true],[1.1,0,300,true],[2.5,.05,301,false],[4,.05,302,true]]) {
    wall=born+offset;
    if(sync) {
      syncAirdrop.call(client,[{id:1,x:12,z:8,s:size,d:landing?1:0}]);
      syncLoot.call(client,[{id:2,x:12,z:8}]);
    }
    updateAirdrop.call(client,delta,wall);updateLoot.call(client,delta,wall);
    record({wall,delta,authority,sync});
  }
  const seedYaw=20000.12345;
  client.airdropMeshes.get(1).rotation.y=seedYaw;
  client.airdropMeshes.get(1).userData.crate.rotation.y=seedYaw;
  client.lootMeshes.get(2).rotation.y=seedYaw;
  let advance=[];
  for(let frame=1;frame<=1800;frame++) {
    wall=born+4+frame/60;
    updateAirdrop.call(client,1/60,wall);updateLoot.call(client,1/60,wall);
    advance.push([wall,1/60,bits(1/60)]);
    if(frame%600===0) {
      record({wall,delta:1/60,authority:302,sync:false,advance,...(frame===600?{seedYaw,seedYawBits:bits(seedYaw)}:{})});
      advance=[];
    }
  }
  programs.push({born,landing,size,steps});
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during clock capture: '+file);
const file='tools/loot_clock_capture.mjs';
const inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/loot_clock.json'),{formatVersion:1,source:{inputs,sourceInputs},programs});
console.log('LOOT_CLOCK_REFERENCES_PASS programs='+programs.length);
