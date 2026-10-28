import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/player_view_body_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabConst,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const data=contents['public/js/data.js'];
const arrow=name=>{
  const pattern=name==='wrapPi'
    ? /^export const wrapPi = \(a\) => \{[\s\S]*?^\};/m
    : new RegExp('^export const '+name+' = [^\\n]+;','m');
  const match=pattern.exec(data);
  if(!match)throw new Error('Missing original camera helper: '+name);
  return match[0].replace(/^export /,'');
};
const definitions=[grabConst(data,'PLAYER_TPS'),...['frictionFPS','lerpFPS','wrapPi','camAngleStep'].map(arrow)].join('\n');
const {PLAYER_TPS,camAngleStep}=new Function(definitions+'\nreturn {PLAYER_TPS,camAngleStep};')();
const method=grabMethod(contents['public/js/game.js'],'_stepThirdPersonBody').trimStart();
const thresholdMatch=/move\.lengthSq\(\) > ([\d.]+)/.exec(method);
if(!thresholdMatch)throw new Error('Missing original movement threshold');
const threshold=Number(thresholdMatch[1]);
const step=new Function('PLAYER_TPS','camAngleStep',
  'return function '+method.slice('_stepThirdPersonBody'.length)+';')(PLAYER_TPS,camAngleStep);
const f=Math.fround;
const below=[f(.0000038999805838102475),0,f(.019999999552965164)];
const above=[f(.00000969995107880095),0,f(.019999997690320015)];
const cases=[
  {name:'below-float-rounds-up',move:below},
  {name:'above-float-rounds-down',move:above},
  {name:'below-negative',move:below.map(value=>-value)},
  {name:'above-negative',move:above.map(value=>-value)},
  {name:'below-swapped',move:[below[2],0,below[0]]},
  {name:'above-swapped',move:[above[2],0,above[0]]},
  {name:'below-with-y',move:[below[0],below[2],0]},
  {name:'above-with-y',move:[above[0],above[2],0]},
  {name:'zero',move:[0,0,0]},
  {name:'ordinary-move',move:[f(-.6),0,f(-.8)]},
  {name:'below-aiming',move:below,aiming:true},
  {name:'below-firing',move:below,firing:true},
  {name:'above-defending',move:above,defending:true},
  {name:'above-fpv',move:above,mode:'fpv'},
  {name:'zero-delta',move:above,delta:0},
];
for(const sample of cases){
  if(!sample.move.every(value=>Object.is(value,f(value))))throw new Error('Movement must be representable by native Vector3');
  const vector=new THREE.Vector3(...sample.move);
  const ctx={viewMode:sample.mode||'tps',defending:!!sample.defending,aiming:!!sample.aiming,
    firing:!!sample.firing,bodyYaw:-.7,yaw:.45};
  sample.initialYaw=ctx.bodyYaw;
  sample.yaw=ctx.yaw;
  sample.delta=sample.delta??1/60;
  sample.movementSquared=vector.lengthSq();
  sample.frames=[];
  for(let i=0;i<12;i++){
    step.call(ctx,sample.delta,vector);
    sample.frames.push(ctx.bodyYaw);
  }
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during body capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Player-view body generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/player_view_body.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},threshold,rate:PLAYER_TPS.BODY_TURN_K,cases});
console.log('PLAYER_VIEW_BODY_REFERENCES_PASS cases='+cases.length);
