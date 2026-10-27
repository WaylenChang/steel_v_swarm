import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_snap_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
// Execute only the original anchor branch and its direct literals/functions.
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const method=grabMethod(game,'_updateSpectator');
const start=method.indexOf('      if (specViewLocked(view) || !this._specAnchorOk');
const end=method.indexOf('      const a = this._specAnchor;',start);
const locked=/export const specViewLocked = \(view\) =>\s*([^;]+);/.exec(data);
const friction=/export const frictionFPS = \(k, dt\) =>\s*([^;]+);/.exec(data);
const lerp=/export const lerpFPS = \(k, dt\) =>\s*([^;]+);/.exec(data);
if(start<0||end<0||!locked||!friction||!lerp)throw new Error('Missing original spectator anchor seams');
const cameraRules=new Function(grabConst(data,'SPEC_CAM')+'\nreturn SPEC_CAM;')();
const specViewLocked=new Function('SPEC_CAM','return (view)=>'+locked[1]+';')(cameraRules);
const frictionFPS=new Function('return (k,dt)=>'+friction[1]+';')();
const lerpFPS=new Function('frictionFPS','return (k,dt)=>'+lerp[1]+';')(frictionFPS);
const advance=new Function('specViewLocked','SPEC_CAM','lerpFPS','view','p','dt',method.slice(start,end));
const f=Math.fround;
const cases=[
  {name:'above-by-small-y',view:'orbit',anchor:[0,0,0],point:[40,f(.001),0],anchorOk:true},
  {name:'above-by-small-z',view:'orbit',anchor:[0,0,0],point:[40,0,f(.001)],anchorOk:true},
  {name:'above-by-tiny-y',view:'orbit',anchor:[0,0,0],point:[40,2**-20,0],anchorOk:true},
  {name:'rounded-double-boundary',view:'orbit',anchor:[0,0,0],point:[40,2**-22,0],anchorOk:true},
  {name:'exact-threshold',view:'orbit',anchor:[0,0,0],point:[40,0,0],anchorOk:true},
  {name:'exact-pythagorean',view:'orbit',anchor:[0,0,0],point:[24,32,0],anchorOk:true},
  {name:'pythagorean-above',view:'orbit',anchor:[0,0,0],point:[24,32,f(.001)],anchorOk:true},
  {name:'one-float-below',view:'orbit',anchor:[0,0,0],point:[40-2**-18,0,0],anchorOk:true},
  {name:'one-float-above',view:'orbit',anchor:[0,0,0],point:[40+2**-18,0,0],anchorOk:true},
  {name:'shifted-above',view:'orbit',anchor:[1000,1000,1000],point:[1040,f(1000.001),1000],anchorOk:true},
  {name:'negative-above',view:'orbit',anchor:[0,0,0],point:[-40,-f(.001),0],anchorOk:true},
  {name:'above-moving',view:'orbit',anchor:[0,0,0],point:[40,f(.001),0],anchorOk:true,delta:1/60},
  {name:'smooth-moving',view:'orbit',anchor:[0,0,0],point:[24,32,0],anchorOk:true,delta:1/60},
  {name:'first-anchor',view:'orbit',anchor:[0,0,0],point:[1,0,0],anchorOk:false},
  {name:'locked-fpv',view:'fpv',anchor:[0,0,0],point:[1,0,0],anchorOk:true},
  {name:'locked-tps',view:'tps',anchor:[0,0,0],point:[1,0,0],anchorOk:true}
];
const bits=value=>{const data=Buffer.alloc(8);data.writeDoubleLE(value);return data.toString('hex');};
for(const sample of cases){
  for(const point of [sample.anchor,sample.point])
    if(!point.every(value=>Object.is(value,f(value))))throw new Error('Input must be exactly representable by native Vector3');
  const anchor=new THREE.Vector3(...sample.anchor),point=new THREE.Vector3(...sample.point);
  const distance=anchor.distanceTo(point),copy=anchor.copy,lerpMethod=anchor.lerp;
  let copied=0,smoothed=0;
  anchor.copy=function(value){copied++;return copy.call(this,value);};
  anchor.lerp=function(value,weight){smoothed++;return lerpMethod.call(this,value,weight);};
  const client={_specAnchor:anchor,_specAnchorOk:sample.anchorOk};
  advance.call(client,specViewLocked,cameraRules,lerpFPS,sample.view,point,sample.delta??0);
  if(copied+smoothed!==1)throw new Error('Original anchor branch did not select exactly one path');
  sample.distance=distance;
  sample.distanceBits=bits(distance);
  sample.result={snap:copied===1,anchor:anchor.toArray(),anchorOk:client._specAnchorOk};
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during spectator snap capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator snap generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_snap.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},cameraRules,cases});
console.log('SPECTATOR_SNAP_REFERENCES_PASS cases='+cases.length);
