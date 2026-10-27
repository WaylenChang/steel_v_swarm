import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_fpv_pose_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const balance=JSON.parse(await readFile(join(root,'data/balance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(contents['public/js/game.js'],'_updateSpectator');
const start=method.indexOf('        const vw = heroView(kind, tgt.ch,');
const end=method.indexOf('\n      } else {',start);
if(start<0||end<0)throw new Error('Missing original spectator FPV branch');
const program=method.slice(start,end);
const profiles=balance.spectator.profiles;
const actors=['s01','s03','t01','t06','t09','m01',''].map(character=>({
  character,profile:character?profiles[character]:balance.spectator.fallbacks.STEEL,
}));
if(actors.some(row=>!row.profile))throw new Error('Missing controlled spectator profile');
const points=[[12,5,-9],[1024,-1024,-1024],[.5,0,-.5],[-2048,2,2048]];
for(const point of points)if(!point.every(value=>Object.is(value,Math.fround(value))))
  throw new Error('Input positions must be exactly representable by native Vector3');
const angles=[0,.7,-1.2,Math.PI/2,-Math.PI/2,1e-8,20000.12345];
const altitudes=[0,balance.spectator.camera.FLY_M,balance.spectator.camera.FLY_M+1];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let capture,runtime;
try{
  const page=await browser.newPage();
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.origin!=='http://source.invalid')return route.abort();
    if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><body></body></html>'});
    if(url.pathname==='/three.module.js')return route.fulfill({contentType:'text/javascript',body:contents['out/forest_review/three.module.js']});
    return route.abort();
  });
  await page.goto('http://source.invalid/');
  ({capture,runtime}=await page.evaluate(async({program,actors,points,angles,altitudes,camera})=>{
    const THREE=await import('/three.module.js');
    const advance=new Function('heroView','SPEC_CAM','kind','tgt','h','a',program);
    const bits=(value,wide)=>{
      const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const capture=[];
    for(const actor of actors)for(const point of points)for(const yaw of angles)for(const altitude of altitudes){
      const tgt={ch:actor.character,heroY:altitude,dead:false,mesh:{visible:true}};
      const context={_specYaw:yaw,camera:{position:new THREE.Vector3()}};
      const heroView=(_kind,_character,flying)=>flying?actor.profile.air:actor.profile.ground;
      advance.call(context,heroView,camera,'controlled',tgt,actor.profile.height,new THREE.Vector3(...point));
      const value=context.camera.position.toArray();
      capture.push({character:actor.character,point,yawBits:bits(yaw,true),altitude,
        cameraBits:value.map(item=>bits(item,true)),cameraFloat32Bits:value.map(item=>bits(item,false)),
        hidden:context._specHid===tgt,visible:tgt.mesh.visible});
    }
    return {capture,runtime:{userAgent:navigator.userAgent}};
  },{program,actors,points,angles,altitudes,camera:balance.spectator.camera}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during FPV pose capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator FPV pose generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_fpv_pose.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,camera:balance.spectator.camera,actors,cases:capture});
console.log('SPECTATOR_FPV_POSE_REFERENCES_PASS cases='+capture.length);
