import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {instrumentAquaticCapture,captureAquaticBundle} from './aquatic_capture.mjs';
import {captureSceneryMotion} from './scenery_motion_capture.mjs';
import {sourceSeaWaveState} from './marine_references.mjs';

export async function captureAquaticPointRasters(page, factorySource) {
  return page.evaluate(async factorySource=>{
    const THREE=await import('three');
    const {AQUATIC}=await import('/js/aquatics.js'),{mulberry32}=await import('/js/rng.js'),{WATER}=await import('/js/data.js');
    const build=new Function('THREE','AQUATIC','mulberry32','WATER','terrainEnvCode',factorySource+'\nreturn createSuspendedDetritus;')(
      THREE,AQUATIC,mulberry32,WATER,()=>1);
    const result=[];
    for(const [width,height,depth,fov,pixelRatio,attenuation] of [[128,128,2,75,1,true],[256,128,8,75,1,true],
      [128,256,8,30,1,true],[128,128,20,110,1,true],[128,128,4,75,2,true],[128,128,4,75,4,false]]) {
      const original=build({waterY:0,minX:-1,maxX:1,minZ:-1,maxZ:1,heightAt:()=>-5},42);
      const points=original.group,sourceColours=points.geometry.attributes.color.array;
      const positions=[-.6,0,0,0,0,0,.6,0,0],colours=[...sourceColours.slice(0,3),...sourceColours.slice(AQUATIC.SNOW_COUNT_WATER*3,AQUATIC.SNOW_COUNT_WATER*3+3),1,1,1];
      const geometry=new THREE.BufferGeometry();
      geometry.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));
      geometry.setAttribute('color',new THREE.Float32BufferAttribute(colours,3));
      points.geometry.dispose();points.geometry=geometry;points.material.sizeAttenuation=attenuation;
      const renderer=new THREE.WebGLRenderer({antialias:false,alpha:false,preserveDrawingBuffer:true});
      renderer.setPixelRatio(pixelRatio);renderer.setSize(width,height,false);renderer.setClearColor(0x000000,1);
      renderer.toneMapping=THREE.NoToneMapping;renderer.outputColorSpace=THREE.SRGBColorSpace;
      const scene=new THREE.Scene();scene.add(points);
      const camera=new THREE.PerspectiveCamera(fov,width/height,.1,100);camera.position.z=depth;
      renderer.render(scene,camera);
      const mat=points.material;
      result.push({width:renderer.domElement.width,height:renderer.domElement.height,depth,fov,pixelRatio,
        source:{positions,colours,batches:[{id:1,count:3}],material:{size:mat.size,opacity:mat.opacity,colour:mat.color.toArray(),
          vertexColors:mat.vertexColors,sizeAttenuation:mat.sizeAttenuation,pixelRatio}},png:renderer.domElement.toDataURL('image/png').split(',')[1]});
      geometry.dispose();mat.dispose();renderer.dispose();renderer.forceContextLoss();
    }
    return result;
  },factorySource);
}

export async function aquaticReferences(source, {extraTimes=[]}={}) {
  const load = path=>import(pathToFileURL(join(source,path)).href);
  const {readSrc,grabFn}=await load('tools/audit_src.mjs');
  const THREE=await load('out/forest_review/three.module.js'), {mulberry32}=await load('public/js/rng.js');
  const data=await load('public/js/data.js'), vessels=await load('public/js/vesselCatalog.js');
  const waveState=sourceSeaWaveState(readSrc('public','js','toon.js'),THREE,grabFn);
  const original=readSrc('public','js','aquatics.js'), instrumented=instrumentAquaticCapture(original,grabFn);
  const constants=/export const AQUATIC = (\{[\s\S]*?\n\});/.exec(original);
  if(!constants)throw new Error('Missing original aquatic constants');
  const AQUATIC=new Function('return ('+constants[1]+');')();
  const code=new Function('WATER',grabFn(readSrc('public','js','biomes.js'),'terrainEnvCode')+'\nreturn terrainEnvCode;')(data.WATER);
  const wind={waveAmp:{value:1}};
  const frozen=new Function('_weatherWind',grabFn(readSrc('public','js','toon.js'),'isWeatherFrozen')+'\nreturn isWeatherFrozen;')(wind);
  const scope={THREE,mulberry32,WATER:data.WATER,AQUATIC,terrainEnvCode:code,markShared:value=>value,
    toonMat:color=>new THREE.MeshBasicMaterial({color}),toonPlain:options=>new THREE.MeshBasicMaterial(options),
    generateVessel:vessels.generateVessel,vesselFitsAt:vessels.vesselFitsAt,setSeaWaveSources:waveState.setSources,
    buildGeneratedVesselMesh:(_v,options={})=>{
      const root=new THREE.Group();
      if(options.wake!==false){const wake=new THREE.Group();root.add(wake);root.userData.wake=wake;}
      return root;
    }};
  const factory=name=>new Function(...Object.keys(scope),grabFn(instrumented,name)+'\nreturn '+name+';')(...Object.values(scope));
  const programs=[];
  for(const mode of ['deep','shallow','mixed','dry','small','no_water']) {
    waveState.setSources([]);
    const group=new THREE.Group(), systems=[];
    const span=mode==='small'?20:500;
    const terrain={minX:-span,maxX:span,minZ:-span,maxZ:span,waterY:mode==='no_water'?null:0,
      heightAt:(x,_z)=>mode==='dry'?4:mode==='shallow'?-1.2:mode==='mixed'?(x<0?-12:1):-12};
    for(const name of ['createBubbleSystem','createSuspendedDetritus','createFishSchools','createJellyfishFields']) {
      const system=factory(name)(terrain,42);
      if(!system)continue;
      if(system.init)system.init();
      system.group.userData.nativeAquatic=system.nativeCapture;
      group.add(system.group);systems.push(system);
    }
    const vessel=factory('createSurfaceVessels')(terrain,42);
    if(vessel)group.add(vessel.group);
    const aquatic=captureAquaticBundle(group,terrain.waterY).aquatics, motions=captureSceneryMotion(group).motions;
    const snapshots=()=>{
      group.updateMatrixWorld(true);
      const matrices=[],pivots=[];
      group.traverse(node=>{
        if(node.userData.nativeAquaticMesh) {
          const matrix=new THREE.Matrix4(),capacity=node.instanceMatrix.count;
          matrices.push({id:node.userData.nativeAquaticMesh,count:node.count,frames:Array.from({length:capacity},(_,i)=>{
            node.getMatrixAt(i,matrix);return matrix.toArray();
          })});
        }
        if(node.userData.nativeMotionId)pivots.push({id:node.userData.nativeMotionId,matrix:node.matrixWorld.toArray()});
      });
      const bubbles=systems.find(system=>system.nativeCapture.kind==='bubble')?.nativeCapture;
      const detritus=systems.find(system=>system.nativeCapture.kind==='detritus')?.nativeCapture;
      return {matrices,pivots,waves:waveState.packet(),bubbles:bubbles?{draws:bubbles.draws,particles:bubbles.particles.map(part=>({...part}))}:null,
        detritus:detritus?{positions:Array.from(detritus.positions),particles:detritus.particles.map(part=>({...part}))}:null};
    };
    const initial=snapshots(),frames=[];
    for(const [delta,time,waveAmp] of [[0,0,1],[.016,.016,1],[.25,.266,0],[8,8.266,.001],
      [0,8.266,.0011],[.25,8.516,1],[-.1,8.416,1],[12,20.416,1],[.25,20.666,.0009],[.25,20.916,1],
      ...extraTimes.map(time=>[.016,time,1])]) {
      wind.waveAmp.value=waveAmp;
      for(const system of systems)system.step(delta,time);
      vessel?.step(delta,time,frozen());
      frames.push({delta,time,waveAmp,result:snapshots()});
    }
    programs.push({mode,source:aquatic,motions,initial,frames,waveCapacity:waveState.WIND.SEA_SOURCE_N});
  }
  return {aquaticPrograms:programs};
}
