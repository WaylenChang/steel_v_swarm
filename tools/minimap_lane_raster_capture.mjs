import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original minimap lane input changed: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const draw=grabMethod(contents['public/js/game.js'],'_drawMinimap');
const begin=draw.indexOf('    this._mmLanes.forEach('),end=draw.indexOf('    ctx.setLineDash([]);',begin);
const start=draw.lastIndexOf('    ctx.lineWidth = ',begin);
const color=contents['public/js/data.js'].match(/export const laneCssColor = \(li\) => \{[\s\S]*?\n\};/)?.[0];
const palette=contents['public/js/data.js'].match(/^export const LANE_COLORS = \[[^\]\n]+\];/m)?.[0];
if(start<0||begin<0||end<0||!color||!palette)throw new Error('Original minimap lane callback changed');
const program={callback:draw.slice(start,end),palette:palette.replace(/^export /,''),
  color:color.replace(/^export /,'')};
const lane=(grade,points)=>points.map(([x,z])=>({x,z,grade}));
const cases=[
  {name:'ground_axis',lanes:[lane('ground',[[8,18],[116,18]])],ids:[0]},
  {name:'ground_fractional',lanes:[lane('ground',[[8.25,18.75],[116.25,18.75]])],ids:[1]},
  {name:'bridge_axis',lanes:[lane('bridge',[[8,30],[116,30]])],ids:[2]},
  {name:'tunnel_axis',lanes:[lane('tunnel',[[8.25,40.5],[116.25,40.5]])],ids:[-1]},
  {name:'bridge_turn',lanes:[lane('bridge',[[8,70],[48,22],[91,71],[120,33]])],ids:[1]},
  {name:'tunnel_turn',lanes:[lane('tunnel',[[8.25,70.75],[48.25,22.25],[91.75,70.5],[120,33]])],ids:[0]},
  {name:'ground_sharp',lanes:[lane('ground',[[12,76],[60,16],[61,75],[116,23]])],ids:[2]},
  {name:'transitions',lanes:[[{x:8,z:70,grade:'ground'},{x:38,z:30,grade:'bridge'},
    {x:70,z:65,grade:'bridge'},{x:95,z:18,grade:'tunnel'},{x:120,z:70,grade:'tunnel'}]],ids:[1]},
  {name:'clipped',lanes:[lane('bridge',[[-30,16],[70,83],[160,12]])],ids:[null]},
  {name:'overlap',lanes:[lane('ground',[[8,48],[120,48]]),lane('bridge',[[64,4],[64,92]]),
    lane('tunnel',[[6,10],[122,86]])],ids:[2,1,0]},
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let captured,runtime;
try{
  const page=await browser.newPage({viewport:{width:128,height:96},deviceScaleFactor:1});
  await page.setContent('<canvas width="128" height="96"></canvas>');
  ({cases:captured,runtime}=await page.evaluate(({program,cases})=>{
    const laneCssColor=new Function(program.palette+'\n'+program.color+'\nreturn laneCssColor;')();
    const render=new Function('laneCssColor','return function(){const ctx=this.mmCtx,w=128,h=96;'+program.callback+'};')(laneCssColor);
    const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
    const casesOut=cases.map(sample=>{
      ctx.reset();ctx.fillStyle='#102030';ctx.fillRect(0,0,128,96);
      const records=[],calls={};let points=[];
      for(const name of ['beginPath','moveTo','lineTo','stroke'])calls[name]=ctx[name];
      ctx.beginPath=function(){points=[];return calls.beginPath.call(this);};
      ctx.moveTo=function(x,y){points.push([x,y]);return calls.moveTo.call(this,x,y);};
      ctx.lineTo=function(x,y){points.push([x,y]);return calls.lineTo.call(this,x,y);};
      ctx.stroke=function(){records.push({points:points.slice(),dash:this.getLineDash(),color:this.strokeStyle,
        width:this.lineWidth,alpha:this.globalAlpha});return calls.stroke.call(this);};
      render.call({mmCtx:ctx,_mmLanes:sample.lanes,cfg:{laneIds:sample.ids},_world2mm:(x,z)=>[x,z]});
      for(const name of Object.keys(calls))ctx[name]=calls[name];
      return {...sample,strokes:records,png:canvas.toDataURL('image/png').split(',')[1]};
    });
    return {cases:casesOut,runtime:{deviceScaleFactor:devicePixelRatio,userAgent:navigator.userAgent}};
  },{program,cases}));
}finally{await browser.close();}
for(const sample of captured){
  const png=Buffer.from(sample.png,'base64');
  if(png.length<24||png.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||png.readUInt32BE(16)!==128||png.readUInt32BE(20)!==96)
    throw new Error('Invalid original lane PNG: '+sample.name);
  sample.sha256=digest(png);
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original lane input changed during capture: '+path);
const inputs={};
for(const path of ['tools/minimap_lane_raster_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/minimap_lane_raster.json'),{formatVersion:1,
  source:{inputs,sourceInputs},browser:browser.version(),runtime,size:[128,96],background:[16,32,48],cases:captured});
console.log('MINIMAP_LANE_RASTER_CAPTURE_PASS cases='+captured.length);
