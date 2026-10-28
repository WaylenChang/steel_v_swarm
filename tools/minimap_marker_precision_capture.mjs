import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/minimap_marker_precision_capture.mjs';
const windowFixture='tests/fixtures/minimap_window_precision.json';
const prior=JSON.parse(await readFile(join(root,windowFixture),'utf8'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const localInputs={};
for(const path of [generator,windowFixture,...Object.keys(prior.source.inputs)]){
  const bytes=await readFile(join(root,path));
  const input=path.endsWith('.mjs')?bytes.toString('utf8').replace(/\r\n?/g,'\n'):bytes;
  localInputs[path]=digest(input);
  if(prior.source.inputs[path]&&prior.source.inputs[path]!==localInputs[path])throw new Error('Stale window input: '+path);
}
const sourceInputs={},sourceContents={};
for(const [path,expected]of Object.entries(prior.source.sourceInputs)){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==expected||expected!==sourceInputs[path])throw new Error('Stale original source: '+path);
  sourceContents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=sourceContents['public/js/game.js'];
const draw=grabMethod(game,'_drawMinimap'),start=draw.indexOf('    for (const ent of this.ents.values()) {');
const end=draw.indexOf('    const label = ',start),width=/ctx.lineWidth = ([\d.]+);/.exec(draw);
if(start<0||end<0||!width)throw new Error('Missing original marker drawing program');
const marker=draw.slice(start,end);
const Client=new Function('sideInfo','return class {\n'+grabMethod(game,'_world2mm')+
  '\n_markers() { const ctx=this.mmCtx,w=this.canvas[0],h=this.canvas[1];\n'+marker+'\n}\n};')
  (side=>({color:'side:'+side}));
const bits=(value,bytes=4)=>{
  const b=Buffer.alloc(bytes);if(bytes===4)b.writeFloatLE(value);else b.writeDoubleLE(value);return b.toString('hex');
};
const number=(hex,bytes)=>bytes===4?Buffer.from(hex,'hex').readFloatLE():Buffer.from(hex,'hex').readDoubleLE();
const position=row=>row.pointBits.map(value=>number(value,4));
const cases=[];
for(const window of prior.cases.filter(row=>['berlin','taroko','dubai','walvisbay'].includes(row.map)&&row.kind==='robot'&&row.near)){
  for(const viewer of ['','STEEL','SWARM']){
    const components=Object.fromEntries(['x0','z0','x1','z1'].map((key,index)=>[key,number(window.componentsBits[index],8)]));
    const pixelPoints=[[5.123456,5.54321],[3.21519,3.67123],[2.12345,2.87654],[215.12345,4.87654],[2.51234,3.41234]];
    const sourcePoints=pixelPoints.map(([x,z])=>[
      bits(Math.fround(components.x0+(components.x1-components.x0)*x/prior.canvas[0])),
      bits(Math.fround(components.z0+(components.z1-components.z0)*z/prior.canvas[1]))]);
    const pointBits=index=>sourcePoints[index%sourcePoints.length];
    const rows=[
      {id:1,kind:'base',side:'STEEL',hero:false,self:false,neutral:false,pointBits:pointBits(0)},
      {id:2,kind:'tower',side:'SWARM',hero:false,self:false,neutral:false,pointBits:pointBits(1)},
      {id:3,kind:'robot',side:'SWARM',hero:true,self:false,neutral:false,pointBits:pointBits(2)},
      {id:4,kind:'heli',side:'STEEL',hero:false,self:false,neutral:false,pointBits:pointBits(3)},
      {id:5,kind:'soldier',side:'GUER',hero:false,self:false,neutral:false,pointBits:pointBits(4)},
      {id:6,kind:'robot',side:'STEEL',hero:true,self:true,neutral:false,pointBits:pointBits(1)},
      {id:7,kind:'bunker',side:'MILI',hero:false,self:false,neutral:false,pointBits:pointBits(2)},
      {id:8,kind:'soldier',side:'SWARM',hero:false,self:false,neutral:true,pointBits:pointBits(3)},
    ];
    const bunkers=[{side:'MILI',pointBits:pointBits(2)},{side:'GUER',pointBits:pointBits(4)}];
    const missiles=[{pointBits:pointBits(4)},{pointBits:pointBits(3)}];
    const heading=viewer==='SWARM'?-1.2345:0.73,trace=[];
    let path=null,transform=null;
    const ctx={lineWidth:Number(width[1]),fillStyle:'',strokeStyle:'',
      fillRect(x,y,w,h){trace.push({shape:this.fillStyle==='#ff5533'?'missile':'rect',fill:true,rectBits:[x,y,w,h].map(v=>bits(v))});},
      strokeRect(x,y,w,h){trace.push({shape:'rect',fill:false,rectBits:[x,y,w,h].map(v=>bits(v)),widthBits:bits(this.lineWidth)});},
      beginPath(){path={points:[]};},arc(x,y,r){path={shape:'circle',center:[x,y],radius:r};},
      moveTo(x,y){path.shape='polygon';path.points.push([x,y]);},lineTo(x,y){path.points.push([x,y]);},closePath(){},
      fill(){if(path.shape==='circle')trace.push({shape:'circle',fill:true,centerBits:path.center.map(v=>bits(v)),radiusBits:bits(path.radius)});
        else trace.push({shape:'polygon',fill:true,positionBits:transform.position.map(v=>bits(v)),rotationBits:bits(transform.rotation),
          pointsBits:path.points.map(pair=>pair.map(v=>bits(v)))});},
      stroke(){trace.push({shape:'circle',fill:false,centerBits:path.center.map(v=>bits(v)),radiusBits:bits(path.radius),widthBits:bits(this.lineWidth)});},
      save(){transform={position:[0,0],rotation:0};},translate(x,y){transform.position=[x,y];},
      rotate(value){transform.rotation=value;},restore(){transform=null;}};
    const client=Object.assign(new Client(),{_mmWin:components,mmCtx:ctx,canvas:prior.canvas,side:viewer,
      pos:{x:number(window.focusBits[0],4),z:number(window.focusBits[1],4)},viewMode:'fpv',yaw:heading,bodyYaw:heading,
      ents:new Map(rows.map(row=>[row.id,{...row,isSelf:row.self,mesh:{position:{x:position(row)[0],z:position(row)[1]}}}])),
      _seenBunkers:new Map(bunkers.map((row,index)=>[index,{side:row.side,x:position(row)[0],z:position(row)[1]}])),
      samMeshes:new Map(missiles.map((row,index)=>[index,{mesh:{position:{x:position(row)[0],z:position(row)[1]}}}]))});
    client._markers();
    cases.push({map:window.map,viewer,componentsBits:window.componentsBits,focusBits:window.focusBits,
      headingBits:bits(heading,8),rows,bunkers,missiles,commands:trace});
  }
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during marker precision capture: '+path);
for(const [path,expected]of Object.entries(localInputs)){
  const bytes=await readFile(join(root,path));
  const input=path.endsWith('.mjs')?bytes.toString('utf8').replace(/\r\n?/g,'\n'):bytes;
  if(digest(input)!==expected)throw new Error('Local input changed during marker precision capture: '+path);
}
await writeFixtureJson(join(root,'tests/fixtures/minimap_marker_precision.json'),{formatVersion:1,
  source:{inputs:localInputs,sourceInputs},canvas:prior.canvas,cases});
console.log('MINIMAP_MARKER_PRECISION_REFERENCES_PASS cases='+cases.length);
