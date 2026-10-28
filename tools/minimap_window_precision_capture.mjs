import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/minimap_window_precision_capture.mjs';
const localFiles=[generator,'data/maps.json','data/balance.json'];
const localInputs={},localContents={};
for(const path of localFiles){
  const bytes=await readFile(join(root,path));
  localContents[path]=bytes.toString('utf8');
  localInputs[path]=digest(path===generator?localContents[path].replace(/\r\n?/g,'\n'):bytes);
}
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},sourceContents={};
for(const path of ['public/js/game.js','public/js/data.js','public/index.html','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  sourceContents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabBlock,grabConst,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=sourceContents['public/js/game.js'],data=sourceContents['public/js/data.js'];
const near=/const MM_NEAR = (\{[\s\S]*?\n\});/.exec(game);
const aim=/\bAIM_SIGHT_MULT:\s*([\d.]+)/.exec(data);
const scale=/export const COMBAT_SCALE = ([\d.]+);/.exec(data);
const canvasMatch=/<canvas\s+id="minimap"\s+width="(\d+)"\s+height="(\d+)"/.exec(sourceContents['public/index.html']);
if(!near||!aim||!scale||!canvasMatch)throw new Error('Missing original minimap rules or canvas');
const rules=new Function('return ('+near[1]+');')();
const balance=JSON.parse(localContents['data/balance.json']);
const units=balance.constants.UNITS,aimValue=balance.constants.GAME.AIM_SIGHT_MULT;
if(aimValue!==Number(aim[1]))throw new Error('Imported aiming sight multiplier differs from source');
const declaredUnits=grabConst(data,'UNITS');
for(const kind of ['robot','drone','morph']){
  const body=kind==='morph'?grabBlock(data,'UNITS.morph ='):grabBlock(declaredUnits,kind+': {');
  const sight=/(?:^|[,;\n])\s*sight:\s*(\d+(?:\.\d+)?)/.exec(body);
  if(!sight||units[kind].sight!==Number(sight[1])*Number(scale[1]))
    throw new Error('Imported '+kind+' sight differs from original scaled source');
}
const methods=['_mmWindow','_world2mm','_world2mmFull','_drawMinimap'].map(name=>grabMethod(game,name));
const Client=new Function('MM_NEAR','GAME','UNITS','return class {\n'+methods.join('\n')+'\n};')
  (rules,{AIM_SIGHT_MULT:aimValue},units);
const labelStatement=/const label = this\.mmMode === 'near'[^\n]+;/.exec(methods[3]);
if(!labelStatement)throw new Error('Missing original minimap label');
const sourceLabel=new Function('v',labelStatement[0]+'\nreturn label;');
const bits=(value,bytes)=>{
  const buffer=Buffer.alloc(bytes);
  if(bytes===8)buffer.writeDoubleLE(value);else buffer.writeFloatLE(value);
  return buffer.toString('hex');
};
function captureReveal(client,window,canvas){
  if(window.x0===window.x1||window.z0===window.z1)return null;
  const point=[Math.fround((window.x0+window.x1)/2),Math.fround((window.z0+window.z1)/2)];
  const noop=()=>{},background={drawImage:noop,clearRect:noop,fillRect:noop};
  const recorded={};let softCenter,softScale=1;
  const scratch={clearRect:noop,beginPath:noop,fill:noop,save:noop,restore:noop,
    ellipse(x,y,rx,ry){recorded.hard={center:[x,y],radius:[rx,ry]};},
    translate(x,y){softCenter=[x,y];},scale(_x,y){softScale=y;},
    createRadialGradient(){return {addColorStop:noop};},
    arc(_x,_y,r){recorded.soft={center:softCenter,radius:[r,r*softScale]};}};
  const ctx={drawImage:noop,fillRect:noop,setLineDash:noop,beginPath:noop,moveTo:noop,lineTo:noop,stroke:noop,
    save:noop,translate:noop,rotate:noop,closePath:noop,fill:noop,restore:noop,measureText:()=>({width:0}),fillText:noop};
  Object.assign(client,{_mmLast:0,_mmWarmUntil:0,_pulseUntil:0,side:'STEEL',youId:17,dead:false,
    _mmBase:{},_mmLanes:[],_seenBunkers:new Map(),ents:new Map(),samMeshes:new Map(),cfg:{},yaw:0,viewMode:'',
    minimapCanvas:{width:canvas[0],height:canvas[1]},mmCtx:ctx,
    _mmSeen:{getContext:()=>background},_mmFog:{getContext:()=>background},_mmScr:{getContext:()=>scratch},
    _mmVision:()=>[[point[0],point[1],90.25]],_mmShadows:()=>null});
  client._drawMinimap(100);
  if(!recorded.hard||!recorded.soft)throw new Error('Original minimap did not draw both reveal circles');
  return {pointBits:point.map(value=>bits(value,4)),radius:90.25,
    hard:{centerBits:recorded.hard.center.map(value=>bits(value,4)),radiusBits:recorded.hard.radius.map(value=>bits(value,4))},
    soft:{centerBits:recorded.soft.center.map(value=>bits(value,4)),radiusBits:recorded.soft.radius.map(value=>bits(value,4))}};
}
const maps=JSON.parse(localContents['data/maps.json']);
const terrains=['berlin','taroko','dubai','walvisbay'].map(id=>{
  const map=maps.find(row=>row.id===id);
  if(!map||!map.variants?.['1']?.bounds)throw new Error('Missing imported source map: '+id);
  return {id,bounds:map.variants['1'].bounds};
});
terrains.push({id:'narrow-axis',bounds:{minX:-83.125,maxX:126.375,minZ:-600.0625,maxZ:710.3125}});
terrains.push({id:'zero-axis',bounds:{minX:10,maxX:10,minZ:-256,maxZ:256}});
terrains.push({id:'tiny-axis',bounds:{minX:0,maxX:0.49999999999999994,minZ:-256,maxZ:256}});
const canvas=[Number(canvasMatch[1]),Number(canvasMatch[2])],cases=[];
for(const terrain of terrains)for(const kind of ['', 'robot','drone','morph']){
  const b=terrain.bounds,sight=units[kind]?.sight||rules.SPEC_R;
  const radius=Math.max(rules.MIN_R,sight*aimValue*rules.PAD);
  const midX=(b.minX+b.maxX)/2,midZ=(b.minZ+b.maxZ)/2;
  const positions=[[0,0],[b.minX,b.minZ],[b.maxX,b.maxZ],[b.minX+radius,midZ],
    [b.maxX-radius,midZ],[midX,b.minZ+radius],[midX,b.maxZ-radius],[0.0001220703125,-0.000244140625]];
  for(const position of positions)for(const nearMode of [false,true]){
    const focus=position.map(Math.fround);
    const client=Object.assign(new Client(),{terrain:b,pos:{x:focus[0],z:focus[1]},heroKind:kind,mmMode:nearMode?'near':'full'});
    const window=client._mmWindow();
    const native=[window.x0,window.z0,window.x1-window.x0,window.z1-window.z0].map(Math.fround);
    const points=[[focus[0],focus[1]],[midX,midZ],[b.minX,b.maxZ],[b.maxX,b.minZ],
      [native[0]+native[2]*0.37,native[1]+native[3]*0.61]].map(pair=>pair.map(Math.fround));
    client._mmWin=window;
    const originals=points.map(point=>client._world2mm(point[0],point[1],canvas[0],canvas[1]));
    // Retain a separate oracle for projection from already-quantized native windows.
    client._mmWin={x0:native[0],z0:native[1],x1:native[0]+native[2],z1:native[1]+native[3]};
    const projections=points.map((point,index)=>({pointBits:point.map(value=>bits(value,4)),
      originalBits:originals[index].map(value=>bits(value,4)),
      resultBits:client._world2mm(point[0],point[1],canvas[0],canvas[1]).map(value=>bits(value,4))}));
    const first=client._world2mmFull(window.x0,window.z0,canvas[0],canvas[1]);
    const last=client._world2mmFull(window.x1,window.z1,canvas[0],canvas[1]);
    const crop=[first[0],first[1],last[0]-first[0],last[1]-first[1]];
    const reveal=captureReveal(client,window,canvas);
    cases.push({map:terrain.id,kind,near:nearMode,
      boundsBits:Object.fromEntries(Object.entries(b).map(([key,value])=>[key,bits(value,8)])),
      focusBits:focus.map(value=>bits(value,4)),windowBits:native.map(value=>bits(value,4)),
      componentsBits:[window.x0,window.z0,window.x1,window.z1].map(value=>bits(value,8)),
      cropBits:crop.map(value=>bits(value,4)),label:sourceLabel.call({mmMode:nearMode?'near':'full'},window),projections,reveal});
  }
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during minimap precision capture: '+path);
for(const [path,expected]of Object.entries(localInputs)){
  const bytes=await readFile(join(root,path));
  const current=path===generator?bytes.toString('utf8').replace(/\r\n?/g,'\n'):bytes;
  if(digest(current)!==expected)throw new Error('Local input changed during minimap precision capture: '+path);
}
await writeFixtureJson(join(root,'tests/fixtures/minimap_window_precision.json'),{formatVersion:1,
  source:{inputs:localInputs,sourceInputs},canvas,cases});
console.log('MINIMAP_WINDOW_PRECISION_REFERENCES_PASS cases='+cases.length);
