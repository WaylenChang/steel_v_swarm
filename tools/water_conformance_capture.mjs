import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const path of ['public/js/game.js','public/js/sceneDisasterGeometry.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original water conformance input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const {grabFn,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=await readFile(join(source,'public/js/game.js'),'utf8');
const disaster=await readFile(join(source,'public/js/sceneDisasterGeometry.js'),'utf8');
const code=grabMethod(game,'_conformWater');
const geometryCode=grabFn(disaster,'ringsGeometry')+'\n'+grabFn(disaster,'brokenGroundGeometry');
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const specs=[];
for(const terrain of ['flat','slope','deck','curved'])for(const radius of [0,6,19.125]) {
  const position=[12.125,-.05,-8.75];
  specs.push({terrain,center:[12.25,-7.5,2.125],children:[
    {type:'cylinder',water:true,position,parameters:{radiusTop:radius,radius:100}},
    {type:'circle',water:true,position:[-2,.32,3],parameters:{radiusTop:null,radius}},
    {type:'sphere',water:true,position:[1,0,-1],parameters:{}},
    {type:'broken',water:true,position:[0,.42,0],parameters:null},
    {type:'box',water:false,position:[2.375,.5,-3.625],parameters:{radiusTop:radius}},
  ]});
}
specs.push({terrain:'flat',center:[-0,0,-0],children:[
  {type:'circle',water:true,position:[0,-0,0],parameters:{radius:-0}},
  {type:'sphere',water:true,position:[0,-.05,0],parameters:{radiusTop:null,radius:null}},
]});
// Original fixed 28-spoke construction, captured before radius multiplication.
specs.push({terrain:'flat',center:[0,0,0],children:[{type:'circle',water:true,position:[0,0,0],parameters:{radius:1}}]});

// Only surface responses and starting model records are probes. The complete
// original method, Three constructors, Float32 normal writes and disposal execute.
function capture(THREE,code,geometryCode,specs) {
  const conform=new Function('THREE','return ({'+code+'})._conformWater;')(THREE);
  const broken=new Function('THREE',geometryCode+'\nreturn brokenGroundGeometry;')(THREE);
  const hex=bytes=>[...new Uint8Array(bytes.buffer,bytes.byteOffset,bytes.byteLength)].map(x=>x.toString(16).padStart(2,'0')).join('');
  const bits=value=>{const data=new Float64Array([value]);return hex(new Uint8Array(data.buffer));};
  return specs.map(spec=>{
    const group=new THREE.Group(),queries=[],disposed=[];
    const originals=spec.children.map((child,index)=>{
      const geometry=child.type==='cylinder'?new THREE.CylinderGeometry(3,3,.1,12):child.type==='circle'?new THREE.CircleGeometry(3,12)
        :child.type==='sphere'?new THREE.SphereGeometry(3,8,4):child.type==='broken'?broken(11,.1):new THREE.BoxGeometry(1,1,1);
      if(child.parameters===null)delete geometry.parameters;
      else geometry.parameters=child.parameters;
      geometry.addEventListener('dispose',()=>disposed.push(index));
      const node=new THREE.Mesh(geometry,new THREE.MeshBasicMaterial());
      node.userData.water=child.water;node.position.fromArray(child.position);
      node.quaternion.set(.5,-.5,.5,.5);node.scale.set(.75,1.5,2);
      group.add(node);return geometry;
    });
    const surface=(x,z)=>{
      const height=spec.terrain==='flat'?2.125:spec.terrain==='slope'?x*.125-z*.0625
        :spec.terrain==='deck'?(x>=8&&x<=20&&z>=-12&&z<=-2?15:0):x*x*.001-z*z*.002;
      queries.push([bits(x),bits(z),bits(height)]);return height;
    };
    const [cx,cz,cy]=spec.center;
    conform.call({_surf:surface,terrain:{heightAt:()=>0}},group,cx,cz,cy);
    const nodes=group.children.map((node,index)=>({replaced:node.geometry!==originals[index],
      position:node.position.toArray().map(bits),quaternion:node.quaternion.toArray().map(bits),scale:node.scale.toArray().map(bits),
      vertices:hex(node.geometry.attributes.position.array),normals:hex(node.geometry.attributes.normal.array),
      indices:node.geometry.index?[...node.geometry.index.array]:[],uv:!!node.geometry.attributes.uv}));
    const bindings=spec.children.map(child=>({water:child.water,position:child.position.map(bits),
      parameters:child.parameters===null?null:Object.fromEntries(Object.entries(child.parameters).map(([key,value])=>[key,value===null?null:bits(value)]))}));
    for(const node of group.children){node.geometry.dispose();node.material.dispose();}
    return {terrain:spec.terrain,center:spec.center.map(bits),bindings,queries,nodes,disposed:disposed.slice(0,nodes.filter(node=>node.replaced).length)};
  });
}
const nodeCases=capture(THREE,code,geometryCode,specs);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let cases;
const runtimeDifferences=[];
try {
  const page=await browser.newPage();
  const module=await readFile(join(source,'out/forest_review/three.module.js'),'utf8');
  await page.route('https://water.invalid/**',route=>route.fulfill({status:200,contentType:route.request().url().endsWith('.js')?'text/javascript':'text/html',
    body:route.request().url().endsWith('.js')?module:'<!doctype html>'}));
  await page.goto('https://water.invalid/');
  cases=await page.evaluate(async ({runner,code,geometryCode,specs})=>{
    const THREE=await import('https://water.invalid/three.js');
    return new Function('THREE','code','geometryCode','specs','return ('+runner+')(THREE,code,geometryCode,specs);')(THREE,code,geometryCode,specs);
  },{runner:capture.toString(),code,geometryCode,specs});
  if(JSON.stringify(cases)!==JSON.stringify(nodeCases)) {
    const compare=(a,b,path='')=>{
      if(JSON.stringify(a)===JSON.stringify(b))return;
      if(a&&b&&typeof a==='object'&&typeof b==='object')for(const key of Object.keys(a))compare(a[key],b[key],path+'.'+key);
      else runtimeDifferences.push({path,node:a,browser:b});
    };
    compare(nodeCases,cases);
  }
} finally {await browser.close();}
for(const [path,hash]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Source changed during water capture: '+path);
const inputs={};
for(const path of ['tools/water_conformance_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const unitRing=cases.at(-1).queries.slice(1).flatMap(query=>query.slice(0,2));
if(unitRing.length!==56)throw new Error('Original water fan must retain all 28 radial directions');
await writeFixtureJson(join(root,'tests/fixtures/water_conformance.json'),{formatVersion:1,source:{inputs,sourceInputs},unitRing,cases,nodeCases,runtimeDifferences});
await writeFixtureJson(join(root,'data/water_conformance.json'),{formatVersion:1,source:{inputs,sourceInputs},unitRing});
console.log('WATER_CONFORMANCE_CAPTURE_PASS '+JSON.stringify({cases:cases.length,runtimeDifferences:runtimeDifferences.length}));
