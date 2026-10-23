import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {instrumentSceneryMotion,captureSceneryMotion} from './scenery_motion_capture.mjs';

export async function sceneryMotionReferences(source) {
  const {readSrc,grabFn} = await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const THREE = await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const {resolveWeatherVisuals} = await import(pathToFileURL(join(source,'public/js/weatherVisuals.js')).href);
  const original = instrumentSceneryMotion(readSrc('public','js','biomes.js'),readSrc('public','js','partMotion.js'));
  const edges = await readFile(join(source,'public/js/edgewall.js'),'utf8');
  const match = /export const EDGE_MOTION = (\{[\s\S]*?\n\});/.exec(edges.replace(/\r\n?/g,'\n'));
  if (!match) throw new Error('Missing original edge motion constants');
  const constants = new Function('return ('+match[1]+');')();
  const material = ()=>new THREE.MeshBasicMaterial();
  const geometry = ()=>new THREE.BoxGeometry(1,1,1);
  const merge = geos=>geos[0].clone(); // Poses do not depend on mesh tessellation/materials.
  const buildPart = new Function('THREE','mergeGeos','partMotionMat',
    grabFn(original.parts,'buildPartMotion')+'\nreturn buildPartMotion;')(THREE,merge,material);
  const programs = [];
  for (const fry of [0,Math.PI/2,-.6]) {
    const group = new THREE.Group(), dynamics = [];
    const state = {time:{value:0},wind:{amp:{value:1},freq:{value:1},waveSpeed:{value:1},shape:{value:{w:1}}},
      windPhase:{value:0},wavePhase:{value:0},gustPhase:{value:0},weather:{}};
    const stepWind = new Function('_windT','_windPhase','_wavePhase','_gustPhase','_weatherWind',
      grabFn(readSrc('public','js','toon.js'),'stepCelWind')+'\nreturn stepCelWind;')(
      state.time,state.windPhase,state.wavePhase,state.gustPhase,state.wind);
    const parts = [];
    for (const axis of ['x','y','z']) for (const kind of ['spin','swing']) for (const speed of [-2,0,1.3])
      parts.push({motion:{id:axis+kind+speed,kind,axis,speed,pivot:[2,3,-1],phase:-.7,
        ...(speed===0?{amplitude:0}:speed<0?{amplitude:.16}:{})}});
    const articulated = buildPart(parts,geometry);
    articulated.position.set(4,5,-6);articulated.rotation.set(.1,fry,.2);articulated.scale.set(-1,2,.8);
    group.add(articulated);dynamics.push(()=>articulated.userData.partMotionUpdate(state.time.value));
    const nested = buildPart([{motion:{id:'nested',kind:'swing',axis:'y',speed:2,pivot:[-1,2,1]}}],geometry);
    nested.position.set(1,2,3);nested.rotation.y=.3;articulated.children[0].add(nested);
    dynamics.push(()=>nested.userData.partMotionUpdate(state.time.value));
    const buildEdge = new Function('THREE','buildPartMotion','scenePartGeometry','wallGeo','mergeGeos','envMat',
      '_we','_wm','_wp','_wq','_ws','celWindTime','celWindAmount','celWaveAmount','celWindHeading','EDGE_MOTION',
      grabFn(original.biomes,'buildEdgeMotion')+'\nreturn buildEdgeMotion;')(
      THREE,buildPart,geometry,geometry,merge,material,new THREE.Euler(),new THREE.Matrix4(),new THREE.Vector3(),new THREE.Quaternion(),new THREE.Vector3(),
      ()=>state.time.value,()=>Math.max(0,state.weather.windAmp??1),()=>Math.max(0,state.weather.waveAmp??1),
      ()=>state.weather.windDir||[1,0],constants);
    const motion = ['rotor','float','machine','smoke','dust'].map((kind,i)=>({g:{},p:[2,3,-1],c:0xffffff,
      motion:{id:kind,kind,pivot:[2,3,-1],phase:i*.7-.3}}));
    buildEdge({group,segs:[{x:-10,ground:7,z:8,fry,water:true,motion}],dynamics});
    const bundle = captureSceneryMotion(group), snapshots = () => {
      group.updateMatrixWorld(true);
      const matrices = [];
      group.traverse(node=>{if(node.userData.nativeMotionId) matrices.push({id:node.userData.nativeMotionId,matrix:node.matrixWorld.toArray()});});
      return matrices;
    };
    const initial = snapshots(), frames = [];
    for (const [index,delta] of [0,.016,8,-1,.25,0,.1,4,.016,.25].entries()) {
      state.weather = {windAmp:[1,0,2,-1][index%4],waveAmp:[1,0,2,-1][index%4],
        wind:[0,25,45,50,70,90,100,120,-20][index%9],
        windFreq:[1,0,2,-1][index%4],waveSpeed:[1,0,0,2][index%4],
        windDir:[[1,0],[-1,0],[0,1],[0,-1],[.049,0],[.05,0],[-.05,0]][index%7]};
      const visuals = resolveWeatherVisuals(state.weather);
      state.wind.freq.value=state.weather.windFreq;
      state.wind.waveSpeed.value=state.weather.waveSpeed;
      state.wind.shape.value.w=visuals.wind.gustSpeed;
      const paused = index===4||index===5;
      articulated.userData.partMotionPaused=paused;
      nested.userData.partMotionPaused=paused;
      stepWind(delta);for(const update of dynamics) update(delta);
      frames.push({delta,weather:state.weather,paused,now:state.time.value,matrices:snapshots(),
        phases:[state.windPhase.value,state.wavePhase.value,state.gustPhase.value],
        windShape:['lean','flutter','gust','gustSpeed'].map(key=>visuals.wind[key]),
        waterShape:['crest','cross','chop','whitecaps'].map(key=>visuals.water[key])});
    }
    programs.push({motions:bundle.motions,initial,frames});
  }
  const waterfalls = [];
  for (const sample of [0,.5,.999999]) {
    const group = new THREE.Group(), dynamics = [], random = Object.create(Math);
    random.random = ()=>sample;
    const build = new Function('THREE','Math','edgeWallInsetM','llToWorld','toonMat','toonPlain',
      grabFn(original.biomes,'buildWaterfalls')+'\nreturn buildWaterfalls;')(
      THREE,random,()=>2,(lat,lng)=>[lat,lng],(color,options)=>new THREE.MeshBasicMaterial({color,...options}),
      options=>new THREE.MeshBasicMaterial(options));
    const terrain = {minX:-100,maxX:100,minZ:-100,maxZ:100,heightAt:(x,z)=>x*.5+z*.25};
    build(group,[{lat:0,lng:0},{lat:20,lng:20},{lat:200,lng:0}],terrain,{},dynamics);
    const bundle = captureSceneryMotion(group), snapshots = () => {
      group.updateMatrixWorld(true);
      const matrices = [];
      group.traverse(node=>{
        if (node.userData.nativeMotionId) matrices.push({id:node.userData.nativeMotionId,
          matrix:node.matrixWorld.toArray(),...(node.userData.nativeSceneryMotion.kind==='waterfall_sheet'?{opacity:node.material.opacity}:{})});
      });
      return matrices;
    };
    const initial = snapshots(), frames = [];
    for (const delta of [0,.016,.1,0,8,-1,.25]) {
      for(const update of dynamics) update(delta);
      frames.push({delta,matrices:snapshots()});
    }
    waterfalls.push({motions:bundle.motions,initial,frames});
  }
  return {sceneryMotionPrograms:programs,waterfallMotionPrograms:waterfalls};
}
