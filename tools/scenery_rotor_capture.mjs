import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {instrumentSceneryMotion,captureSceneryMotion} from './scenery_motion_capture.mjs';
import {sceneryMotionReferences} from './scenery_motion_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/biomes.js','public/js/partMotion.js','public/js/edgewall.js','public/js/toon.js','public/js/weatherVisuals.js',
  'out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {readSrc,grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const original=instrumentSceneryMotion(readSrc('public','js','biomes.js'),readSrc('public','js','partMotion.js'));
const match=/export const EDGE_MOTION = (\{[\s\S]*?\n\});/.exec(readSrc('public','js','edgewall.js'));
if(!match)throw new Error('Missing original edge motion constants');
const constants=new Function('return ('+match[1]+');')();
const programs=[];
for(const fry of [0,Math.PI/2,-.6])for(const phase of [-200000.12345,0,200000.12345]) {
  const group=new THREE.Group(),dynamics=[],state={now:0,weather:{windAmp:1,windDir:[1,0]}};
  const unexpected=()=>{throw new Error('Rotor capture must not substitute another scenery builder');};
  const build=new Function('THREE','buildPartMotion','scenePartGeometry','wallGeo','mergeGeos','envMat',
    '_we','_wm','_wp','_wq','_ws','celWindTime','celWindAmount','celWaveAmount','celWindHeading','EDGE_MOTION',
    grabFn(original.biomes,'buildEdgeMotion')+'\nreturn buildEdgeMotion;')(
    // Geometry is excluded: the fixture observes the original parent/pivot transforms only.
    THREE,unexpected,unexpected,()=>new THREE.BoxGeometry(1,1,1),geometries=>{
      if(geometries.length!==1)throw new Error('Rotor pose capture expects one geometry');
      return geometries[0].clone();
    },()=>new THREE.MeshBasicMaterial(),
    new THREE.Euler(),new THREE.Matrix4(),new THREE.Vector3(),new THREE.Quaternion(),new THREE.Vector3(),
    ()=>state.now,()=>Math.max(0,state.weather.windAmp),()=>1,()=>state.weather.windDir,constants);
  build({group,segs:[{x:-10,ground:7,z:8,fry,water:true,motion:[{g:{},p:[2,3,-1],c:0xffffff,
    motion:{id:'rotor',kind:'rotor',pivot:[2,3,-1],phase}}]}],dynamics});
  const bundle=captureSceneryMotion(group);
  let rotor;
  group.traverse(node=>{if(node.userData.nativeSceneryMotion?.kind==='rotor')rotor=node;});
  if(bundle.motions.length!==1||!rotor)throw new Error('Expected one original rotor');
  const snapshot=()=>{group.updateMatrixWorld(true);return {matrix:rotor.matrixWorld.toArray(),rotation:rotor.rotation.toArray().slice(0,3)};};
  const initial=snapshot(),frames=[];
  for(const [delta,windAmp,windDir]of [[0,1,[1,0]],[.016,1,[0,-1]],[8,2,[0,1]],[-1,1,[-1,0]],
    [.25,0,[1,0]],[.1,1,[.049,0]],[.1,1,[.05,0]],[.1,1,[-.05,0]]]) {
    state.weather={windAmp,windDir};state.now+=Math.max(0,Math.min(.25,delta));
    for(const update of dynamics)update(delta);
    frames.push({delta,weather:state.weather,now:state.now,...snapshot()});
  }
  for(let segment=0;segment<3;segment++) {
    state.weather={windAmp:1,windDir:segment%2?[0,1]:[0,-1]};
    for(let frame=0;frame<600;frame++) {
      state.now+=1/60;for(const update of dynamics)update(1/60);
    }
    frames.push({delta:1/60,repeat:600,weather:state.weather,now:state.now,...snapshot()});
  }
  programs.push({motions:bundle.motions,initial,frames});
}
const referencePrograms=await sceneryMotionReferences(source);
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during capture: '+file);
const inputs={};
for(const file of ['tools/scenery_rotor_capture.mjs','tools/scenery_motion_capture.mjs','tools/scenery_motion_references.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/scenery_rotor.json'),{formatVersion:1,source:{inputs,sourceInputs},programs,referencePrograms});
console.log('SCENERY_ROTOR_REFERENCES_PASS programs='+programs.length);
