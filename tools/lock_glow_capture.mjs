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
for(const path of ['public/js/vfx.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original lock-glow input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const text=(await readFile(join(source,'public/js/vfx.js'),'utf8')).replace(/\r\n?/g,'\n');
let clock=0;
let phase=0,sine=0;
const math=Object.create(Math);
math.sin=value=>{phase=value;sine=Math.sin(value);return sine;};
// Only the shared glow texture is a probe; execute the original meshes, materials and render callback.
const texture=new THREE.Texture();
const lockGlow=new Function('THREE','performance','glowTexture','Math','return '+grabFn(text,'lockGlow'))(
  THREE,{now:()=>clock},()=>texture,math);
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
let cases=[];
for(const dimensions of [{height:1,radius:.2,top:1},{height:4,radius:2,top:6},{height:12,radius:15,top:30}]) {
  const target=new THREE.Group();
  const glow=lockGlow(target,0x44aaee,{h:dimensions.height,r:dimensions.radius,top:dimensions.top});
  const [halo,ring]=glow.children;
  for(const now of [0,.016,.25,1,5.125,100,10000.125,1000000.125,100000000.125,10000000000.125]) {
    clock=now*1000;
    if(clock/1000!==now)throw new Error('Unrepresentable native second input');
    for(const age of [null,0,.000001,.05,.199,.199999999,.2,.200000001,.201,-.01]) {
      const hit=age===null?-1e9:(clock-age*1000)/1000;
      // Native public flash timestamps are seconds. Preserve exactly that input at the source seam.
      glow.userData.flashAt=hit*1000;
      glow.onBeforeRender();ring.updateMatrix();
      const matrix=ring.matrix.elements,scale=ring.scale.x;
      const mapped=column=>[matrix[column*4]/scale,matrix[column*4+1]/scale,-matrix[column*4+2]/scale];
      const pose={centre:halo.position.y,halo_size:halo.scale.x,halo_opacity:halo.material.opacity,
          ring_scale:scale,ring_opacity:ring.material.opacity,ring_angle:-ring.rotation.z,
          radius:Math.max(1.5,dimensions.radius*1.5)};
      cases.push({dimensions,nowBits:bits(now),hitBits:bits(hit),pose,
        phaseBits:bits(phase),sineBits:bits(sine),
        poseBits:Object.fromEntries(Object.entries(pose).map(([key,value])=>[key,bits(value)])),
        basis:[mapped(0),mapped(2),mapped(1)]});
    }
  }
  for(const child of glow.children){child.geometry?.dispose();child.material.dispose();}
  target.clear();
}
texture.dispose();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Lock-glow trigonometry qualification requires the original Chromium runtime');
await mkdir(join(root,'artifacts/sol'),{recursive:true});
const previousDirectory=process.cwd(),executablePath=chromePath();
let browser,browserVersion;
try {
  process.chdir(join(root,'artifacts/sol'));
  browser=await chromium.launch({headless:true,executablePath});
  browserVersion=browser.version();
  const page=await browser.newPage();
  cases=await page.evaluate(async({moduleUrl,constructor,inputs})=>{
    const THREE=await import(moduleUrl);
    let clock=0,phase=0,sine=0;
    const math=Object.create(Math);
    math.sin=value=>{phase=value;sine=Math.sin(value);return sine;};
    const texture=new THREE.Texture();
    const build=new Function('THREE','performance','glowTexture','Math','return '+constructor)(
      THREE,{now:()=>clock},()=>texture,math);
    const directBuild=new Function('THREE','performance','glowTexture','return '+constructor)(
      THREE,{now:()=>clock},()=>texture);
    const bits=value=>{
      const bytes=new Uint8Array(8);new DataView(bytes.buffer).setFloat64(0,value,true);
      return [...bytes].map(value=>value.toString(16).padStart(2,'0')).join('');
    };
    const number=hex=>new DataView(Uint8Array.from(hex.match(/../g),part=>parseInt(part,16)).buffer).getFloat64(0,true);
    const output=inputs.map(item=>{
      const dimensions=item.dimensions,target=new THREE.Group();
      const glow=build(target,0x44aaee,{h:dimensions.height,r:dimensions.radius,top:dimensions.top});
      const [halo,ring]=glow.children;
      clock=number(item.nowBits)*1000;
      glow.userData.flashAt=number(item.hitBits)*1000;
      glow.onBeforeRender();ring.updateMatrix();
      if(bits(phase)!==item.phaseBits)throw new Error('Original browser/Node pulse input phases disagree');
      const matrix=ring.matrix.elements,scale=ring.scale.x;
      const mapped=column=>[matrix[column*4]/scale,matrix[column*4+1]/scale,-matrix[column*4+2]/scale];
      const pose={centre:halo.position.y,halo_size:halo.scale.x,halo_opacity:halo.material.opacity,
        ring_scale:scale,ring_opacity:ring.material.opacity,ring_angle:-ring.rotation.z,
        radius:Math.max(1.5,dimensions.radius*1.5)};
      const direct=directBuild(new THREE.Group(),0x44aaee,{h:dimensions.height,r:dimensions.radius,top:dimensions.top});
      direct.userData.flashAt=number(item.hitBits)*1000;
      direct.onBeforeRender();
      const [directHalo,directRing]=direct.children;
      for(const [key,value]of Object.entries({halo_size:directHalo.scale.x,halo_opacity:directHalo.material.opacity,
        ring_scale:directRing.scale.x,ring_opacity:directRing.material.opacity,ring_angle:-directRing.rotation.z}))
        if(bits(pose[key])!==bits(value))throw new Error('Sine observation changed the original browser callback: '+key);
      for(const child of direct.children){child.geometry?.dispose();child.material.dispose();}
      direct.parent.remove(direct);
      for(const child of glow.children){child.geometry?.dispose();child.material.dispose();}
      target.clear();
      return {dimensions,nowBits:item.nowBits,hitBits:item.hitBits,pose,
        poseBits:Object.fromEntries(Object.entries(pose).map(([key,value])=>[key,bits(value)])),
        phaseBits:bits(phase),sineBits:bits(sine),nodePoseBits:item.poseBits,nodeSineBits:item.sineBits,
        basis:[mapped(0),mapped(2),mapped(1)]};
    });
    texture.dispose();return output;
  },{moduleUrl:'data:text/javascript;base64,'+(await readFile(join(source,'out/forest_review/three.module.js'))).toString('base64'),
    constructor:grabFn(text,'lockGlow'),inputs:cases});
} finally {
  try {if(browser)await browser.close();}
  finally {process.chdir(previousDirectory);}
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during lock-glow capture: '+path);
const inputs={};
for(const path of ['tools/lock_glow_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/lock_glow.json'),{formatVersion:1,
  source:{inputs,sourceInputs,runtime:{node:process.version,v8:process.versions.v8,chromium:browserVersion}},cases});
console.log('LOCK_GLOW_CAPTURE_PASS '+JSON.stringify({cases:cases.length}));
