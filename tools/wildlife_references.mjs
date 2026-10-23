import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {instrumentWildlifeCapture,captureWildlifeBundle} from './wildlife_capture.mjs';
import {wildlifeDensityReferences} from './wildlife_density_references.mjs';

export async function wildlifeReferences(source) {
  const load = file=>import(pathToFileURL(join(source,file)).href);
  const {readSrc,grabFn} = await load('tools/audit_src.mjs');
  const THREE = await load('out/forest_review/three.module.js');
  const wildlife = await load('public/js/wildlife.js'), data = await load('public/js/data.js');
  const {lodSlot} = await load('public/js/lod.js');
  const {resolveWeatherVisuals} = await load('public/js/weatherVisuals.js');
  const biomes = readSrc('public','js','biomes.js');
  const instrumented = instrumentWildlifeCapture(biomes,readSrc('public','js','wildlifeRender.js'),readSrc('public','js','ground.js'));
  const catalogInstrumented = instrumentWildlifeCapture(biomes,readSrc('public','js','wildlifeRender.js'),readSrc('public','js','ground.js'),true);
  const groundFunctions = ['obbDist','obbNear','footNear','makeFootprintIndex','blockerFoot'];
  const ground = new Function(groundFunctions.map(name=>grabFn(instrumented.ground,name)).join('\n')
    +'\nreturn {makeFootprintIndex,blockerFoot};')();
  const terrainCode = new Function('WATER',grabFn(biomes,'terrainEnvCode')+'\nreturn terrainEnvCode;')(data.WATER);
  const programs = [],densityPrograms=[];
  for (const mode of ['dry','wet','split','missing']) for (const selection of ['all','bird','fish','pets','small','stress','empty','no_anchors']) {
    const group = new THREE.Group(), calls = [];
    const height = (x,z)=>mode==='missing'&&x>0?NaN:mode==='wet'?-4:mode==='split'?(x<0?-4:4):10+x*.01-z*.005;
    const terrain = {minX:-180,maxX:180,minZ:-180,maxZ:180,waterY:0,heightAt:height,inDryBand:(_x,z)=>Math.abs(z)<4};
    const pref = key=>selection==='empty'?0:['all','stress','no_anchors'].includes(selection)?1.5:selection==='bird'?+(key==='birds'):selection==='fish'?+(key==='fish')
      :selection==='pets'?+(key==='cats'||key==='dogs'):+(key==='wildlife');
    const buildOriginal = new Function('THREE','compileSceneParts','scenePartGeometry','mergeGeos','lodSlot','envMat',
      'celWindTime','getWeatherDynamics',...['wildlifeInit','wildlifeStep','wildlifeHeading','animalParts','wingAngle','tailAngle','specSpringPS'],
      'unitScale',grabFn(instrumented.render,'buildWildlifeBatches')+'\nreturn buildWildlifeBatches;')(
      THREE,()=>new THREE.BoxGeometry(),()=>new THREE.BoxGeometry(),geos=>geos[0],lodSlot,()=>new THREE.MeshBasicMaterial(),
      ()=>0,()=>({activity:1}),...['wildlifeInit','wildlifeStep','wildlifeHeading','animalParts','wingAngle','tailAngle','specSpringPS'].map(key=>wildlife[key]),new THREE.Vector3(1,1,1));
    const builders = ['planFlockRoutes','planFishRoutes','planCatRoutes','planDogRoutes','planSmallAnimalRoutes'];
    const buildOf = (program,rosters,preferences) => new Function('THREE','edgeWallInsetM','terrainEnvCode','makeFootprintIndex','blockerFoot','visualPref',
      'BIRDS_OFF','FISH_OFF','CATS_OFF','DOGS_OFF','SMALL_ANIMALS',...builders,'objHeightMax','buildWildlifeBatches',
      grabFn(program,'buildFlocks')+'\nreturn buildFlocks;')(
      THREE,()=>12,terrainCode,ground.makeFootprintIndex,ground.blockerFoot,preferences,false,false,false,false,wildlife.SMALL_ANIMALS,
      ...builders.map(key=>selection==='stress'?(...args)=>wildlife[key](...args).map(route=>({...route,count:200})):wildlife[key]),
      ()=>110,(...args)=>{const result=buildOriginal(...args);rosters.push({root:args[0],options:args[2],result});return result;});
    const build=buildOf(instrumented.biomes,calls,pref);
    const anchors = {shore:Array.from({length:24},(_,i)=>[Math.cos(i/24*Math.PI*2)*75-40,Math.sin(i/24*Math.PI*2)*75]),
      groves:[{x:50,z:40,r:22},{x:-60,z:-60,r:18}],landmarks:[{x:55,z:-45,r:16}],
      settlements:[{x:0,z:35,r:18},{x:-40,z:45,r:20}],streets:[{x:30,z:-25,r:20}]};
    const blockers = [{x:0,z:0,r:8},{x:-30,z:20,hw2:8,hd2:2,ry:.7,r:Math.hypot(8,2)},
      {x:64,z:-64,hw2:4,hd2:0,ry:0,r:4}];
    build(group,terrain,[],{anchors:selection==='no_anchors'?{}:anchors,low:false,blockers});
    const bundle = captureWildlifeBundle(group).wildlife;
    const snapshots = () => calls.map(({root})=>{
      const original = root.userData.nativeWildlife, matrices=[];
      root.traverse(node=>{
        if(!node.userData.nativeWildlifeMesh)return;
        const matrix = new THREE.Matrix4();
        matrices.push({id:node.userData.nativeWildlifeMesh,frames:Array.from({length:node.count},(_,index)=>{
          node.getMatrixAt(index,matrix);return matrix.toArray();
        })});
      });
      return {low:original.low,states:original.states.map(({st})=>({t:st.t,pos:Array.from(st.pos),vel:Array.from(st.vel)})),matrices};
    });
    const initial = snapshots(), frames = [];
    for (const [index,[delta,time,activity]] of [[0,0,1],[.016,.016,1],[.1,.116,.5],[4,.366,.15],[0,.366,0],
      [-1,.5,1],[.016,12,1],[.25,12.25,.999],[.016,12.266,1],[.1,12.366,1],[NaN,13,1],[.1,NaN,1]].entries()) {
      const snap = index===7;
      terrain.waterY = index===8?12:0;
      if(snap)for(const {root} of calls)for(const {st} of root.userData.nativeWildlife.states)wildlife.wildlifeSnap(st);
      for(const {result} of calls) result.update(delta,time,{activity});
      frames.push({delta:Number.isFinite(delta)?delta:null,time:Number.isFinite(time)?time:null,snap,activity,waterY:terrain.waterY,variants:snapshots()});
    }
    const habitat = [];
    for(const [x,z] of [[0,0],[8.5,0],[8.49999,0],[-30,20],[-40,20],[64,-59.5],[64,-59.50001],[-100,-100],[100,100],[-64,-64]])
      habitat.push({x,z,height:Number.isFinite(height(x,z))?height(x,z):null,code:terrainCode(terrain,x,z),
        dry:terrain.inDryBand(x,z),valid:calls[0].options.validAt(x,z),wet:calls[0].options.wetAt(x,z),
        occupied:calls[0].root.userData.nativeWildlife.occupied.near({x,z,r:.5})});
    programs.push({mode,source:bundle,initial,frames,habitat});
    if(mode==='split'&&['all','stress','no_anchors'].includes(selection))densityPrograms.push(wildlifeDensityReferences({
      THREE,catalogProgram:catalogInstrumented.biomes,originalProgram:instrumented.biomes,buildOf,terrain,
      anchors:selection==='no_anchors'?{}:anchors,blockers,mode}));
  }
  const activity = [];
  for(const wind of [0,50,100,150])for(const effectiveRain of [0,.3,1])for(const effectiveSnow of [0,1]) {
    const dyn={wind,effectiveRain,effectiveSnow,effectiveSand:.2};
    const profile=resolveWeatherVisuals(dyn);
    activity.push({dyn,value:Math.max(.15,1-Math.max(profile.rain.strength,profile.snow.strength,profile.sand.strength,profile.wind.strength*.8))});
  }
  return {wildlifePrograms:programs,wildlifeActivity:activity,wildlifeDensityPrograms:densityPrograms};
}
