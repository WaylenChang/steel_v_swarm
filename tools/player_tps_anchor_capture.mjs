import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/player_tps_anchor_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const balance=JSON.parse(await readFile(join(root,'data/balance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabConst,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(contents['public/js/game.js'],'_updatePlayer');
const start=method.indexOf('      const h = this.selfH;');
const end=method.indexOf('      this.camera.lookAt(',start);
if(start<0||end<0)throw new Error('Missing original TPS anchor and floor branch');
const program={camera:method.slice(start,end),rules:grabConst(contents['public/js/data.js'],'PLAYER_TPS')};
const positions=[[12,20,-9],[1024,-1024,-1024],[.5,0,-.5],[-2048,2,2048]];
if(positions.some(point=>point.some(value=>!Object.is(value,Math.fround(value)))))
  throw new Error('Position must be representable by native Vector3');
const actors=['t01','t04','s01'].map(character=>({character,height:balance.cameraProfiles[character].ground.height}));
const angles=[0,.7,-1.2,Math.PI/2,20000.12345];
const pitches=[0,-.25,.7,1.4];
const floors=[0,50,null];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let capture,runtime,rules;
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
  ({capture,runtime,rules}=await page.evaluate(async({program,positions,actors,angles,pitches,floors})=>{
    const THREE=await import('/three.module.js');
    const rules=new Function(program.rules+'\nreturn PLAYER_TPS;')();
    const advance=new Function('PLAYER_TPS','_TMP_A','_TMP_B','_TMP_C',program.camera);
    const bits=(value,wide)=>{
      const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const capture=[];
    for(const actor of actors)for(const point of positions)for(const yaw of angles)for(const pitch of pitches)for(const floor of floors){
      let surfacePoint;
      const context={selfH:actor.height,yaw,pitch,pos:new THREE.Vector3(...point),
        camera:{position:new THREE.Vector3()},_surf:(x,z,y)=>{surfacePoint=[x,y,z];return floor===null?NaN:floor;}};
      advance.call(context,rules,new THREE.Vector3(),new THREE.Vector3(),new THREE.Vector3());
      if(!surfacePoint)throw new Error('Original surface query was not reached');
      capture.push({character:actor.character,point,yawBits:bits(yaw,true),pitchBits:bits(pitch,true),floor,
        queryBits:surfacePoint.map(value=>bits(value,false)),cameraBits:context.camera.position.toArray().map(value=>bits(value,false))});
    }
    return {capture,runtime:{userAgent:navigator.userAgent},rules};
  },{program,positions,actors,angles,pitches,floors}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during TPS anchor capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Player TPS anchor generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/player_tps_anchor.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,rules,actors,cases:capture});
console.log('PLAYER_TPS_ANCHOR_REFERENCES_PASS cases='+capture.length);
