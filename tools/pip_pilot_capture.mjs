import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/pip_pilot_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=contents['public/js/game.js'];
const pip=/const PIP = (\{[^\n]+\});/.exec(game);
if(!pip)throw new Error('Missing original PiP rules');
const rules=new Function('return ('+pip[1]+');')();
const THREE={Color:class{}};
const Pip=new Function('PIP','THREE','lowPower','sideInfo',
  'return class {\n'+grabMethod(game,'_pipSources')+'\n'+grabMethod(game,'_renderPips')+'\n};')
  (rules,THREE,()=>false,()=>({color:'#4fc3f7'}));
const meshes=[7,9].map(id=>({id,visible:true,position:{x:id,y:10,z:0}}));
const entities=new Map(meshes.map(mesh=>[mesh.id,{id:mesh.id,pid:17,hero:false,isSelf:false,
  dead:false,decoy:true,lost:false,si:0,ry:0,mesh}]));
let draws=[];
const renderer={getClearColor:value=>value,getClearAlpha:()=>1,setClearColor:()=>{},setScissorTest:()=>{},
  setScissor:()=>{},setViewport:()=>{},clear:()=>{},render:()=>draws.push({hidden:meshes.filter(mesh=>!mesh.visible).map(mesh=>mesh.id),cockpit:context.cockpit.visible})};
const position={x:0,y:0,z:0,copy(value){Object.assign(this,value);return this;}};
const context=Object.assign(new Pip(),{side:'STEEL',dead:false,isDrone:false,youId:17,_resScale:1,ents:entities,
  renderer,scene:{},canvas:{clientWidth:320,clientHeight:568},cockpit:{visible:true},
  pipCam:{position,rotation:{set(){}},updateProjectionMatrix(){}}});
const cases=[];
for(const [phase,dead,side] of [['alive',false,'STEEL'],['dead',true,'STEEL'],['revived',false,'STEEL'],['no-side',false,'']]){
  context.dead=dead;context.side=side;draws=[];
  const selected=context._pipSources().map(row=>row.ent.id);
  context._renderPips();
  cases.push({phase,dead,side,selected,draws,restored:context.cockpit.visible&&meshes.every(mesh=>mesh.visible)});
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during PiP pilot capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('PiP pilot generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/pip_pilot.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},cases});
console.log('PIP_PILOT_REFERENCES_PASS cases='+cases.length);
