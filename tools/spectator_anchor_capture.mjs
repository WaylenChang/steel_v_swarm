import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_anchor_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
// This oracle evaluates the original anchor branch and its direct dependencies only.
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const method=grabMethod(game,'_updateSpectator');
const start=method.indexOf('      if (specViewLocked(view) || !this._specAnchorOk');
const end=method.indexOf('      const a = this._specAnchor;',start);
const locked=/export const specViewLocked = \(view\) =>\s*([^;]+);/.exec(data);
const friction=/export const frictionFPS = \(k, dt\) =>\s*([^;]+);/.exec(data);
const lerp=/export const lerpFPS = \(k, dt\) =>\s*([^;]+);/.exec(data);
if(start<0||end<0||!locked||!friction||!lerp)throw new Error('Missing original spectator anchor seams');
const program={cameraRules:grabConst(data,'SPEC_CAM'),branch:method.slice(start,end),
  locked:locked[1],friction:friction[1],lerp:lerp[1]};
const f=Math.fround,step=2**-13;
const sequences=[
  {name:'small-motion-240',anchor:[1024,0,0],anchorOk:true,steps:[
    ...Array.from({length:200},()=>({view:'orbit',point:[1024+step,0,0],delta:1/240})),
    {view:'orbit',point:[1064+step,0,0],delta:1/240}]},
  {name:'negative-motion-60',anchor:[-2048,3,-4],anchorOk:true,steps:
    Array.from({length:120},()=>({view:'orbit',point:[-2048-2**-12,3,-4],delta:1/60}))},
  {name:'moving-three-axes',anchor:[1000,10,-500],anchorOk:true,steps:
    Array.from({length:90},(_,i)=>({view:'orbit',point:[f(1000+i*.006),f(10+i*.002),f(-500-i*.004)],delta:1/60}))},
  {name:'view-and-anchor-reset',anchor:[1024,0,0],anchorOk:true,steps:[
    ...Array.from({length:32},()=>({view:'orbit',point:[1024+step,0,0],delta:1/240})),
    {view:'fpv',point:[1024+step,1,0],delta:1/60},
    {view:'orbit',point:[1024+2*step,1,0],delta:1/240},
    {view:'tps',point:[1024+3*step,2,0],delta:1/60},
    {view:'orbit',point:[1024+4*step,2,0],delta:1/240,anchorOk:false},
    {view:'orbit',point:[1024+5*step,2,0],delta:1/240}]},
  {name:'nonpositive-and-mixed-delta',anchor:[1024,0,0],anchorOk:true,steps:[
    {view:'orbit',point:[1034,0,0],delta:-.016},
    {view:'orbit',point:[1024+step,0,0],delta:0},
    ...[1/30,1/60,1/240,.1].map(delta=>({view:'orbit',point:[1024+step,0,0],delta}))]}
];
for(const sequence of sequences)for(const point of [sequence.anchor,...sequence.steps.map(row=>row.point)])
  if(!point.every(value=>Object.is(value,f(value))))throw new Error('Input must be exactly representable by native Vector3');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let capture,runtime,cameraRules;
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
  ({capture,runtime,cameraRules}=await page.evaluate(async ({program,sequences})=>{
    const THREE=await import('/three.module.js');
    const rules=new Function(program.cameraRules+'\nreturn SPEC_CAM;')();
    const locked=new Function('SPEC_CAM','return (view)=>'+program.locked+';')(rules);
    const friction=new Function('return (k,dt)=>'+program.friction+';')();
    const lerp=new Function('frictionFPS','return (k,dt)=>'+program.lerp+';')(friction);
    const advance=new Function('specViewLocked','SPEC_CAM','lerpFPS','view','p','dt',program.branch);
    const bits=(value,wide)=>{
      const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const capture=sequences.map(sequence=>{
      const anchor=new THREE.Vector3(...sequence.anchor),copy=anchor.copy,interpolate=anchor.lerp;
      let copied=false;
      anchor.copy=function(value){copied=true;return copy.call(this,value);};
      anchor.lerp=function(value,weight){return interpolate.call(this,value,weight);};
      const client={_specAnchor:anchor,_specAnchorOk:sequence.anchorOk},frames=[];
      for(const step of sequence.steps){
        if(Object.hasOwn(step,'anchorOk'))client._specAnchorOk=step.anchorOk;
        const point=new THREE.Vector3(...step.point),distance=anchor.distanceTo(point);
        const originalExp=Math.exp;
        let argument,exponential,alpha;
        try{
          Math.exp=value=>{argument=value;exponential=originalExp(value);return exponential;};
          alpha=lerp(rules.POS_K,step.delta);
        }finally{Math.exp=originalExp;}
        copied=false;
        advance.call(client,locked,rules,lerp,step.view,point,step.delta);
        const value=anchor.toArray();
        const reset=Object.hasOwn(step,'anchorOk')?{setAnchorOk:step.anchorOk}:{};
        frames.push({...step,...reset,deltaBits:bits(step.delta,true),snap:copied,anchorOk:client._specAnchorOk,distanceBits:bits(distance,true),
          argumentBits:bits(argument,true),exponentialBits:bits(exponential,true),alphaBits:bits(alpha,true),
          anchorBits:value.map(item=>bits(item,true)),anchorFloat32Bits:value.map(item=>bits(item,false))});
      }
      return {name:sequence.name,anchor:sequence.anchor,anchorOk:sequence.anchorOk,frames};
    });
    return {capture,runtime:{userAgent:navigator.userAgent},cameraRules:rules};
  },{program,sequences}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during spectator anchor capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator anchor generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_anchor.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,cameraRules,sequences:capture});
console.log('SPECTATOR_ANCHOR_REFERENCES_PASS sequences='+capture.length+' frames='+capture.reduce((n,row)=>n+row.frames.length,0));
