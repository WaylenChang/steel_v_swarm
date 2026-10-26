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
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original fire input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const original=async path=>(await readFile(join(source,path),'utf8')).replace(/\r\n?/g,'\n');
const game=await original('public/js/game.js'),data=await original('public/js/data.js'),hazards=await original('public/js/hazards.js');
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const {grabFn,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const constants=data.match(/export const FIRE_WEATHER = \{[\s\S]*?\n\};/)?.[0];
if(!constants)throw new Error('Missing original fire weather thresholds');
const weatherRules=new Function(constants.replace('export ','')+'\nreturn FIRE_WEATHER;')();
const fireDotMul=new Function('FIRE_WEATHER','return '+grabFn(data,'fireDotMul'))(weatherRules);
const stepFireVisual=new Function('return '+grabFn(hazards,'stepFireVisual'))();
const update=new Function('fireDotMul','stepFireVisual','return ({'+grabMethod(game,'_updateLoot')+'})._updateLoot;')(fireDotMul,stepFireVisual);
const balance=JSON.parse(await readFile(join(root,'data/balance.json'),'utf8'));
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const inputs={};
for(const path of ['tools/fire_clock_capture.mjs','tools/fixture_json.mjs','data/balance.json'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const programs=[];
for(const [key,profile]of Object.entries(balance.hazard_visuals)) {
  if(!profile.fx?.flames.length&&!profile.fx?.smoke.length)continue;
  const path='data/hazards/'+key+'.json',raw=await readFile(join(root,path),'utf8');inputs[path]=digest(raw.replace(/\r\n?/g,'\n'));
  const graph=JSON.parse(raw),group=new THREE.Group();
  // Declared node probes consume the imported FX records; constructor geometry is a separate gate.
  const nodes=rows=>rows.map(row=>{
    const object=new THREE.Object3D(),initial=graph.nodes.find(node=>node.id===row.id);
    object.position.fromArray(row.origin);object.scale.fromArray(row.scale);
    object.rotation.set(...initial.trs.r,initial.rotationOrder);
    object.material={opacity:row.opacity,depthWrite:graph.materials[initial.materials[0]].depthWrite};object.userData={ph:row.phase,h0:row.height,
      fireOrigin:new THREE.Vector3(...row.origin),fireScale:new THREE.Vector3(...row.scale),fireOpacity:row.opacity};
    object.userData.id=row.id;group.add(object);return object;
  });
  group.userData.flames=nodes(profile.fx.flames);group.userData.smoke=nodes(profile.fx.smoke);
  let weather={};const context={lootMeshes:new Map(),flamers:[group],envFx:{getWeatherDynamics:()=>weather}};
  const frames=[];
  const weatherCases=[{rain:100}, {}, {rain:0,snow:0,wind:100,windDir:[.6,-.8]}, {rain:55.0001,snow:0,wind:65,windDir:[1,0]},
    {rain:77.5,snow:0,wind:100,windDir:[1,0]}, {rain:100,snow:0,wind:100,windDir:[1,0]},
    {rain:0,snow:100,wind:100,windDir:[-1,0]}, {rain:0,snow:0,wind:-30,windDir:[0,1]}];
  for(const now of [0,.125,1,3.7,3.7,100000000.123456,100000000.123457])for(const state of weatherCases) {
    weather=state;const delta=frames.length%2===0?0:99;
    update.call(context,delta,now);
    const snapshot=rows=>rows.map(node=>({id:node.userData.id,visible:node.visible,position:node.position.toArray(),
      scale:node.scale.toArray(),quaternion:node.quaternion.toArray(),opacity:node.material.opacity,depthWrite:node.material.depthWrite}));
    frames.push({nowBits:bits(now),authority:frames.length%2===0?-100000:100000,deltaBits:bits(delta),weather,
      strengthBits:bits(fireDotMul(weather)),flames:snapshot(group.userData.flames),smoke:snapshot(group.userData.smoke)});
  }
  programs.push({key,frames});
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during fire capture: '+path);
await writeFixtureJson(join(root,'tests/fixtures/fire_clock.json'),{formatVersion:1,source:{inputs,sourceInputs},weatherRules,programs});
console.log('FIRE_CLOCK_CAPTURE_PASS '+JSON.stringify({programs:programs.length,frames:programs.reduce((count,item)=>count+item.frames.length,0)}));
