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
for(const path of ['public/js/game.js','public/js/data.js','public/js/hazards.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original mine input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const original=async path=>(await readFile(join(source,path),'utf8')).replace(/\r\n?/g,'\n');
const game=await original('public/js/game.js'),data=await original('public/js/data.js'),hazards=await original('public/js/hazards.js');
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const {grabFn,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const config=data.match(/\n  MINES: (\{[\s\S]*?\})/)?.[1];
if(!config)throw new Error('Missing original mine display rules');
const rules=new Function('return ('+config+');')();
const initialCheck=Number(/this\._mineCheckAt = ([^;]+);/.exec(game)?.[1]);
if(!Number.isFinite(initialCheck))throw new Error('Missing original mine throttle initialization');
const update=new Function('GAME','return ({'+grabMethod(game,'_updateMines')+'})._updateMines;')({MINES:rules});
// The original constructor owns initial visibility/opacity; only geometry/toon shading are probes.
const build=new Function('THREE','scenePartGeometry','toonMat','return '+grabFn(hazards,'buildMineBump'))(THREE,
  ()=>new THREE.BufferGeometry(),(color,options)=>new THREE.MeshBasicMaterial({color,...options}));
const round=point=>point.map(Math.fround);
const points=[[0,.05,0],[12,5,-8],[-26,.05,3]].map(round);
const mines=points.map(point=>{const mine=build();mine.position.fromArray(point);return mine;});
const client={mineMeshes:new Map(mines.map((mine,index)=>[index+1,mine])),_mineCheckAt:initialCheck,pos:new THREE.Vector3()};
const bits=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const snapshot=()=>mines.map((mine,index)=>({id:index+1,visible:mine.visible,opacity:mine.material.opacity}));
const initial=snapshot(),frames=[];
const observers=[[0,0,0],[30,.05,.001],[30,.05,.0000003],[29.999998092651367,.05,0],[30.000001907348633,.05,0],
  [14,.05,0],[14.000000953674316,.05,0],[3,4.05,0],[0,100,0],[100000008,.05,.01]];
const sample=(observer,now)=>{
  observer=round(observer);client.pos.fromArray(observer);update.call(client,now);
  frames.push({observer,nowBits:bits(now),lastCheckBits:bits(client._mineCheckAt),mines:snapshot(),
    distances:points.map(point=>bits(Math.hypot(...observer.map((value,index)=>value-point[index]))))});
};
sample(observers[0],0);sample(observers[0],.11999999999999998);sample(observers[0],.12);
sample(observers[1],.23999999999999996);sample(observers[1],.24);
for(let index=0;index<observers.length;index++)sample(observers[index],1+index*.12);
sample(observers[0],.18);sample(observers[1],10000000.125);sample(observers[0],10000000.244999997);
const distances=[];
for(const first of [[0,0,0],[-0,-0,-0],[30,0,.001],[30,0,.0000003],[1e-20,-2e-20,3e-20],
  [3.4e38,-3.4e38,3.4e38],[Infinity,NaN,0],[NaN,0,0]]) {
  const a=round(first),b=round(first.map(value=>Number.isFinite(value)?-value:0));
  const value=Math.hypot(...a.map((part,index)=>part-b[index]));
  distances.push({first:a.map(bits),second:b.map(bits),kind:Number.isNaN(value)?'nan':Number.isFinite(value)?'finite':'inf',bits:bits(value)});
}
let seed=0x51de;
const coordinate=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return Math.fround((seed/4294967296-.5)*80);};
for(let index=0;index<256;index++) {
  const first=[coordinate(),coordinate(),coordinate()],second=[coordinate(),coordinate(),coordinate()];
  const value=Math.hypot(...first.map((part,axis)=>part-second[axis]));
  distances.push({first:first.map(bits),second:second.map(bits),kind:'finite',bits:bits(value)});
}
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Mine edge qualification requires the original Chromium runtime');
await mkdir(join(root,'artifacts/sol'),{recursive:true});
const previousDirectory=process.cwd(),executablePath=chromePath();
let browser;
let browserVersion;
try {
  // Chromium/ANGLE can emit debug.log relative to their inherited working directory.
  process.chdir(join(root,'artifacts/sol'));
  browser=await chromium.launch({headless:true,executablePath});
  browserVersion=browser.version();
  const page=await browser.newPage();
  const actual=await page.evaluate(({method,rules,points,initial,initialCheck,frames,distances})=>{
    const update=new Function('GAME','return ({'+method+'})._updateMines;')({MINES:rules});
    const bits=value=>{const buffer=new ArrayBuffer(8);new DataView(buffer).setFloat64(0,value,true);return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');};
    const number=hex=>{const bytes=Uint8Array.from(hex.match(/../g),part=>parseInt(part,16));return new DataView(bytes.buffer).getFloat64(0,true);};
    const mines=points.map((point,index)=>({position:{x:point[0],y:point[1],z:point[2]},visible:initial[index].visible,material:{opacity:initial[index].opacity}}));
    const context={mineMeshes:new Map(mines.map((mine,index)=>[index+1,mine])),_mineCheckAt:initialCheck,pos:{}};
    const states=[];
    for(const frame of frames) {
      context.pos={x:frame.observer[0],y:frame.observer[1],z:frame.observer[2]};update.call(context,number(frame.nowBits));
      states.push({lastCheckBits:bits(context._mineCheckAt),mines:mines.map(mine=>({visible:mine.visible,opacityBits:bits(mine.material.opacity)})),
        distances:points.map(point=>bits(Math.hypot(...frame.observer.map((value,index)=>value-point[index]))))});
    }
    return {states,distances:distances.map(item=>bits(Math.hypot(...item.first.map((part,index)=>number(part)-number(item.second[index])))))};
  },{method:grabMethod(game,'_updateMines'),rules,points,initial,initialCheck,frames,distances});
  const expected={states:frames.map(frame=>({lastCheckBits:frame.lastCheckBits,mines:frame.mines.map(mine=>({visible:mine.visible,opacityBits:bits(mine.opacity)})),distances:frame.distances})),
    distances:distances.map(item=>item.bits)};
  if(JSON.stringify(actual)!==JSON.stringify(expected))throw new Error('Chromium and Node original mine programs disagree');
} finally {
  try {if(browser)await browser.close();}
  finally {process.chdir(previousDirectory);}
}
for(const mine of mines){mine.geometry.dispose();mine.material.dispose();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during mine capture: '+path);
const inputs={};
for(const path of ['tools/mine_view_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/mine_view.json'),{formatVersion:1,source:{inputs,sourceInputs,runtime:{node:process.version,v8:process.versions.v8,chromium:browserVersion}},
  rules:{see:rules.SEE_M,clear:rules.CLEAR_M,initialCheck},points,initial,frames,distances});
console.log('MINE_VIEW_CAPTURE_PASS '+JSON.stringify({frames:frames.length,distances:distances.length}));
