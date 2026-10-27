import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/minimap_marker_raster_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
// The isolated marker callback uses these source literals, not the data module's RNG imports.
for(const path of ['public/js/game.js','public/js/data.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const draw=grabMethod(game,'_drawMinimap');
const start=draw.indexOf('    for (const ent of this.ents.values()) {');
const end=draw.indexOf('    const label = ',start);
const width=/ctx.lineWidth = ([\d.]+);/.exec(draw);
const side=/export const sideInfo = \(s\) =>\s*([^;]+);/.exec(data);
const superSide=/export const SUPER_SIDE = ('[^']+');/.exec(data);
if(start<0||end<0||!width||!side||!superSide)throw new Error('Missing original minimap marker seams');
const program={callback:draw.slice(start,end),lineWidth:Number(width[1]),
  literals:[grabConst(data,'SIDES'),grabConst(data,'THIRD'),grabConst(data,'SUPER_INFO')].join('\n'),
  superSide:superSide[1],sideInfo:side[1]};
const row=(kind,side,x,y,extra={})=>({kind,side,point:[x,y],hero:false,isSelf:false,neutral:false,...extra});
const inputs=[
  {name:'base-integer',viewer:'',rows:[row('base','STEEL',32,32)],bunkers:[],own:null,yaw:0},
  {name:'base-fractional',viewer:'',rows:[row('base','SWARM',32.25,32.75)],bunkers:[],own:null,yaw:0},
  {name:'tower-fractional',viewer:'',rows:[row('tower','GUER',32.25,32.75)],bunkers:[],own:null,yaw:0},
  {name:'hero-friendly',viewer:'STEEL',rows:[row('robot','STEEL',32.25,32.75,{hero:true})],bunkers:[],own:[-500,-500],yaw:0},
  {name:'hero-enemy',viewer:'STEEL',rows:[row('robot','SWARM',32.25,32.75,{hero:true})],bunkers:[],own:[-500,-500],yaw:0},
  {name:'npc-friendly',viewer:'STEEL',rows:[row('soldier','STEEL',32.25,32.75)],bunkers:[],own:[-500,-500],yaw:0},
  {name:'npc-enemy',viewer:'STEEL',rows:[row('soldier','SWARM',32.25,32.75)],bunkers:[],own:[-500,-500],yaw:0},
  {name:'heli-enemy',viewer:'STEEL',rows:[row('heli','SWARM',32.25,32.75)],bunkers:[],own:[-500,-500],yaw:0},
  {name:'bunker-fractional',viewer:'',rows:[],bunkers:[{x:32.25,z:32.75,side:'MILI'}],own:null,yaw:0},
  {name:'arrow-rotated',viewer:'STEEL',rows:[],bunkers:[],own:[32.25,32.75],yaw:.73},
  {name:'inherited-stroke',viewer:'STEEL',rows:[row('robot','SWARM',20,30,{hero:true}),row('base','STEEL',60.25,32.75)],bunkers:[],own:[-500,-500],yaw:0},
  {name:'overlap-and-clip',viewer:'SWARM',rows:[row('heli','STEEL',2.25,6.75),row('soldier','GUER',61.25,38.75),
    row('tower','SWARM',61.25,38.75),row('robot','SWARM',80,38,{hero:true,isSelf:true}),row('soldier','MILI',100,50,{neutral:true})],
    bunkers:[{x:65,z:41,side:'GUER'}],own:[62.5,42.5],yaw:-2.1}
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let cases,runtime;
try{
  const page=await browser.newPage({viewport:{width:128,height:96},deviceScaleFactor:1});
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.href==='http://source.invalid/')return route.fulfill({contentType:'text/html',body:'<!doctype html><canvas width="128" height="96"></canvas>'});
    return route.abort();
  });
  await page.goto('http://source.invalid/');
  ({cases,runtime}=await page.evaluate(({program,inputs})=>{
    const sideInfo=new Function(program.literals+'\nconst SUPER_SIDE='+program.superSide+';\nreturn (s)=>'+program.sideInfo+';')();
    const render=new Function('sideInfo','return function(){const ctx=this.mmCtx,w=128,h=96;'+program.callback+'};')(sideInfo);
    const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
    const cases=inputs.map(sample=>{
      ctx.reset();ctx.fillStyle='#102030';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.lineWidth=program.lineWidth;
      render.call({mmCtx:ctx,side:sample.viewer,pos:{x:sample.own?.[0]??0,z:sample.own?.[1]??0},
        viewMode:'fpv',yaw:sample.yaw,bodyYaw:sample.yaw,
        ents:new Map(sample.rows.map((row,index)=>[index,{...row,mesh:{position:{x:row.point[0],z:row.point[1]}}}])),
        _world2mm:(x,z)=>[x,z],_seenBunkers:new Map(sample.bunkers.map((row,index)=>[index,row])),samMeshes:new Map()});
      return {...sample,png:canvas.toDataURL('image/png').split(',')[1]};
    });
    return {cases,runtime:{deviceScaleFactor:devicePixelRatio,userAgent:navigator.userAgent}};
  },{program,inputs}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const sample of cases){
  const png=Buffer.from(sample.png,'base64');
  if(png.length<24||png.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||png.readUInt32BE(16)!==128||png.readUInt32BE(20)!==96)
    throw new Error('Invalid original minimap marker PNG: '+sample.name);
  sample.sha256=digest(png);
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during marker capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Minimap marker generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/minimap_marker_raster.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,size:[128,96],background:[16,32,48],cases});
console.log('MINIMAP_MARKER_RASTER_REFERENCES_PASS cases='+cases.length);
