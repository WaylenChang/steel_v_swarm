import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/pip_selection_capture.mjs';
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
const game=contents['public/js/game.js'],pip=/const PIP = (\{[^\n]+\});/.exec(game);
if(!pip)throw new Error('Missing original PiP rules');
const rules=new Function('return ('+pip[1]+');')();
const power={low:false},THREE={Color:class{}};
const Pip=new Function('PIP','THREE','lowPower','sideInfo',
  'return class {\n'+grabMethod(game,'_pipSources')+'\n'+grabMethod(game,'_renderPips')+'\n};')
  (rules,THREE,()=>power.low,()=>({color:'#4fc3f7'}));
const entity=(id,drone,extra={})=>({id,pid:17,hero:drone,isSelf:false,dead:false,decoy:!drone,lost:false,si:0,ry:0,
  mesh:{visible:true,revision:0,position:{x:id,y:10,z:-id}},...extra});
const scenarios=[];
for(const drone of [false,true]){
  const ids=drone?[20,21,22]:[7,9,11];
  const rows=ids.map(id=>entity(id,drone));
  if(!drone)rows[2].lost=true;
  else rows[2].dead=true;
  const entities=new Map(rows.map(row=>[row.id,row]));
  let draws=[];
  const position={x:0,y:0,z:0,copy(value){Object.assign(this,value);return this;}};
  const camera={position,rotation:{y:0,set(_x,y){this.y=y;}},updateProjectionMatrix(){}};
  const renderer={getClearColor:value=>value,getClearAlpha:()=>1,setClearColor:()=>{},setScissorTest:()=>{},
    setScissor:()=>{},setViewport:()=>{},clear:()=>{},render:()=>draws.push({
      id:[...entities.values()].find(row=>!row.mesh.visible).id,
      position:[position.x,position.y,position.z],yaw:camera.rotation.y})};
  const context=Object.assign(new Pip(),{side:'STEEL',dead:false,isDrone:drone,youId:17,_resScale:1,
    ents:entities,renderer,scene:{},canvas:{clientWidth:320,clientHeight:568},cockpit:{visible:true},pipCam:camera});
  const steps=[];
  const record=phase=>{
    draws=[];
    const selected=context._pipSources().map(row=>row.ent.id);
    context._renderPips();
    steps.push({phase,low:power.low,rows:[...entities.values()].map(row=>({id:row.id,hero:row.hero,dead:row.dead,modelRevision:row.mesh.revision,
      decoy:row.decoy,lost:row.lost,yaw:row.ry,position:[row.mesh.position.x,row.mesh.position.y,row.mesh.position.z]})),
      selected,draws,restored:context.cockpit.visible&&[...entities.values()].every(row=>row.mesh.visible)});
  };
  power.low=false;record('initial');
  if(drone)rows[0].dead=true;else rows[0].lost=true;
  record('first-unavailable');
  if(drone)rows[1].dead=true;else rows[1].lost=true;
  record('empty');
  if(drone)rows[2].dead=false;else rows[2].lost=false;
  record('recover');
  const extra=entity(drone?23:13,drone);entities.set(extra.id,extra);
  record('append');
  rows[2].mesh.position={x:111,y:20,z:-8};rows[2].ry=1.2;
  record('move');
  rows[2].mesh={visible:true,revision:1,position:{x:-31,y:14,z:19}};
  record('replace-model');
  power.low=true;record('low-power');
  power.low=false;record('full-power');
  if(drone)rows[0].dead=false;else rows[0].lost=false;
  record('restore-first');
  if(!drone){rows[0].dead=true;record('dead-decoy');}
  entities.delete(rows[0].id);record('remove-first');
  scenarios.push({drone,steps});
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during PiP selection capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('PiP selection generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/pip_selection.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},scenarios});
console.log('PIP_SELECTION_REFERENCES_PASS scenarios='+scenarios.length+' frames='+scenarios.reduce((sum,row)=>sum+row.steps.length,0));
