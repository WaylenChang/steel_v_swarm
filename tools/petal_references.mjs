import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {instrumentPetalCapture,capturePetalBundle} from './petal_capture.mjs';

export async function petalReferences(source, {groundedSpin=null,seasons=['spring','summer','autumn','winter'],
  modes=['flat','slope','wet','missing','empty','dense']}={}) {
  const load = path=>import(pathToFileURL(join(source,path)).href);
  const {readSrc,grabFn} = await load('tools/audit_src.mjs');
  const THREE = await load('out/forest_review/three.module.js');
  const petals = await load('public/js/petals.js'), data = await load('public/js/data.js');
  const original = readSrc('public','js','biomes.js'), instrumented = instrumentPetalCapture(original,grabFn);
  const code = new Function('WATER',grabFn(original,'terrainEnvCode')+'\nreturn terrainEnvCode;')(data.WATER);
  const programs = [];
  for (const season of seasons) for (const mode of modes) {
    if(mode==='dense'&&season!=='summer')continue;
    const group = new THREE.Group(), calls = [];
    const height = (x,z)=>mode==='missing'&&x>0?NaN:mode==='slope'?x*.02+z*.01:mode==='wet'?(x>0?-3:data.WATER.SWAMP_BAND+1):0;
    const terrain = {heightAt:height,waterY:mode==='wet'?0:null};
    let weather = {};
    const foliage = new THREE.BoxGeometry(mode==='dense'?160:8,1,mode==='dense'?160:8);
    const crown = new Function(grabFn(original,'foliageCrown')+'\nreturn foliageCrown;')();
    const build = new Function('THREE','TREE_SPECIES','VEG_DEFS','foliageCrown','treePhenology','createForestTree','forestSeed',
      'planPetalFields','terrainEnvCode','lowPower','petalRnd','petalTones','ENV','PETAL','petalGeo','envMat','stepPetal','getWeatherDynamics',
      grabFn(instrumented,'buildPetals')+'\nreturn buildPetals;')(
      THREE,{}, {fixture:{parts:[{key:'foliage',g:foliage,y:2}]}},crown,
      ()=>{throw new Error('Motion-only petal fixture must use its declared foliage crown');},()=>{throw new Error('Unexpected forest tree fixture');},()=>0,
      petals.planPetalFields,code,()=>false,petals.petalRnd,petals.petalTones,data.ENV,petals.PETAL,
      ()=>new THREE.PlaneGeometry(1,1),(color,{transparent,opacity,depthWrite,side})=>new THREE.MeshBasicMaterial({color,transparent,opacity,depthWrite,side}),petals.stepPetal,()=>weather);
    const items = {fixture:[]};
    const centers=mode==='dense'?Array.from({length:8},(_,i)=>[i*220+20,20]):[[-160,-160],[-40,50],[-6,150],[130,20],[230,130]];
    if(mode!=='empty')for(const [cx,cz] of centers)
      for(const [dx,dz] of [[0,0],[2,0],[0,2],[2,2]])items.fixture.push({x:cx+dx,z:cz+dz,y:height(cx+dx,cz+dz),s:1});
    for(const low of [false,true]) {
      const root = new THREE.Group(), callbacks = [];
      group.add(root);
      build(root,terrain,items,season,petals.petalSeason(season),callbacks,42,low);
      calls.push({root,callbacks});
    }
    if(groundedSpin!==null)for(const {root} of calls)for(const part of root.userData.nativePetals.parts)
      Object.assign(part,{a:groundedSpin,y:0,groundTime:1,fade:1,lifted:false,wasGrounded:false});
    const bundle = capturePetalBundle(group).petals;
    const snapshot = () => calls.map(({root})=>{
      const source = root.userData.nativePetals;
      return {low:source.low,time:source.time||0,parts:source.parts.map(part=>({...part})),matrices:source.meshes.flatMap(mesh=>{
        if(!mesh)return [];
        const matrix = new THREE.Matrix4();
        return [{id:mesh.userData.nativePetalMesh,frames:Array.from({length:mesh.count},(_,index)=>{
          mesh.getMatrixAt(index,matrix);return matrix.toArray();
        })}];
      })};
    });
    const initial = snapshot(), frames = [];
    for(let index=0;index<(mode==='dense'?8:100);index++) {
      const delta = index===0||index===45?0:index===12?4:index===13?-1:index===14?NaN:index===15?Infinity:.25;
      weather = {windAmp:index<22?1:index<55?2.5:index<75?.4:1,windDir:index%2?[.6,.8]:[-1,0]};
      for(const {callbacks} of calls)for(const update of callbacks)update(delta);
      frames.push({delta:Number.isFinite(delta)?delta:null,deltaKind:Number.isNaN(delta)?'nan':delta===Infinity?'infinity':'finite',
        weather:{...weather},variants:snapshot()});
    }
    programs.push({season,mode,source:bundle,initial,frames,...(groundedSpin===null?{}:{groundedSpin})});
  }
  const planned = petals.planPetalFields(Array.from({length:4},(_,i)=>({x:20+i,z:20+i,top:2,r:8})),
    {mode:'leaf',groundAt:()=>0,dryAt:()=>true},petals.petalRnd(123));
  if(!planned.parts.length)throw new Error('Missing original petal transition fixture');
  const transitions = [];
  for(const override of [{y:.01,vy:1,groundTime:0,lifted:false},{y:0,groundTime:.05,lifted:false},
    {y:0,groundTime:1,lifted:false},{y:0,groundTime:1,lifted:true},{h:.1,y:0,groundTime:1,lifted:false}]) {
    const part = {...planned.parts[0],...override}, initial={...part}, frames=[];
    for(const [delta,time,dynamics] of [[0,0,null],[.25,.25,{windAmp:2.5,windDir:[.6,.8]}],
      [-1,.25,{windAmp:.4,windDir:[1]}],[NaN,.25,{windAmp:'2.5',windDir:[NaN,1]}],
      [Infinity,.5,{}],[0,NaN,{windAmp:2.5}],[.05,.55,{windAmp:1.6}],
      [.25,.8,{windAmp:1.05}],[.25,1.05,{windAmp:.95}],[.25,1.3,{windAmp:true}]]) {
      petals.stepPetal(part,delta,time,dynamics);
      frames.push({delta:Number.isFinite(delta)?delta:null,deltaKind:delta===Infinity?'infinity':Number.isNaN(delta)?'nan':'finite',
        time:Number.isFinite(time)?time:null,dynamics,part:{...part}});
    }
    transitions.push({initial,frames});
  }
  return {petalPrograms:programs,petalTransitions:transitions,petalRules:{...petals.PETAL}};
}
