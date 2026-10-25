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
for(const file of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Source changed; refresh shared metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {grabMethod,grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const data=(await readFile(join(source,'public/js/data.js'),'utf8')).replace(/\r\n?/g,'\n');
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const constant=name=>{
  const declaration=data.match(new RegExp('export const '+name+' = \\{[\\s\\S]*?\\n\\};'))?.[0];
  if(!declaration)throw new Error('Missing original clock constant: '+name);
  return new Function(declaration.replace('export ','')+'\nreturn '+name+';')();
};
const AIRDROP=constant('AIRDROP'),FIRE_WEATHER=constant('FIRE_WEATHER');
const fireFunction=grabFn(data,'fireDotMul');
const fireDotMul=new Function('FIRE_WEATHER','return '+fireFunction)(FIRE_WEATHER);
const methods=Object.fromEntries(['_syncAirdrop','_updateAirdrop','_syncLoot','_updateLoot'].map(name=>[name,grabMethod(game,name)]));

function capture(THREE,methods,AIRDROP,fireDotMul) {
  const bits=value=>{
    const bytes=new Uint8Array(8);new DataView(bytes.buffer).setFloat64(0,value,true);
    return [...bytes].map(value=>value.toString(16).padStart(2,'0')).join('');
  };
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
  const scope={THREE,AIRDROP,performance:{now:()=>wall*1000},buildAirdrop,buildLoot,
    fireDotMul,stepFireVisual:()=>{throw new Error('Clock fixture must not substitute fire visuals');}};
  const method=name=>new Function(...Object.keys(scope),'return ({'+methods[name]+'})['+JSON.stringify(name)+'];')(...Object.values(scope));
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
  return programs;
}
const nodePrograms=capture(THREE,methods,AIRDROP,fireDotMul);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Loot clock qualification requires the original Chromium runtime');
await mkdir(join(root,'artifacts/sol'),{recursive:true});
const previousDirectory=process.cwd(),executablePath=chromePath();
let browser,browserVersion,programs;
try {
  process.chdir(join(root,'artifacts/sol'));
  browser=await chromium.launch({headless:true,executablePath});
  browserVersion=browser.version();
  const page=await browser.newPage();
  programs=await page.evaluate(async({moduleUrl,captureFunction,methods,AIRDROP,FIRE_WEATHER,fireFunction})=>{
    const THREE=await import(moduleUrl);
    const run=new Function('return '+captureFunction)();
    const fireDotMul=new Function('FIRE_WEATHER','return '+fireFunction)(FIRE_WEATHER);
    return run(THREE,methods,AIRDROP,fireDotMul);
  },{moduleUrl:'data:text/javascript;base64,'+(await readFile(join(source,'out/forest_review/three.module.js'))).toString('base64'),
    captureFunction:capture.toString(),methods,AIRDROP,FIRE_WEATHER,fireFunction});
} finally {
  try {if(browser)await browser.close();}
  finally {process.chdir(previousDirectory);}
}
const tape=rows=>rows.map(program=>program.steps.map(step=>({delta:step.deltaBits,yaw:step.drop.yawBits,
  crateYaw:step.drop.crateYawBits,lootYaw:step.loot.yawBits,born:step.drop.born,
  chute:step.drop.chute,groundChute:step.drop.groundChute,halo:step.drop.halo})));
if(JSON.stringify(tape(nodePrograms))!==JSON.stringify(tape(programs)))
  throw new Error('Original Node and Chromium clock phase/landing programs disagree');
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during clock capture: '+file);
const inputs={};
for(const file of ['tools/loot_clock_capture.mjs','tools/fixture_json.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/loot_clock.json'),{formatVersion:1,
  source:{inputs,sourceInputs,runtime:{node:process.version,v8:process.versions.v8,chromium:browserVersion}},programs});
console.log('LOOT_CLOCK_REFERENCES_PASS programs='+programs.length);
