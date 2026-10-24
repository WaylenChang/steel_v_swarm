import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {trainReferences,readTrainRules} from './train_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/biomes.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const biomes=(await readFile(join(source,'public/js/biomes.js'),'utf8')).replace(/\r\n?/g,'\n');
const rules=readTrainRules(biomes,await readFile(join(source,'out/forest_review/three.module.js'),'utf8'));
const fixtures=await trainReferences(source);
const worldPath='data/worlds/berlin_1_autumn.json';
const worldBytes=await readFile(join(root,worldPath));
const world=JSON.parse(worldBytes);
if(world.trainsCaptured!==true||!world.trains?.length)throw new Error('Missing captured original seasonal train paths');
for(const original of world.trains) {
  if(Object.entries(rules).some(([key,value])=>original[key]!==value))throw new Error('Captured train rules differ from original source');
  const train=new THREE.Group();
  new THREE.Matrix4().fromArray(original.initialFrame).decompose(train.position,train.quaternion,train.scale);
  const line={pts:original.points.map(point=>new THREE.Vector3(...point)),total:original.total};
  const sample=original.start/original.total;
  const random=Object.create(Math);random.random=()=>sample;
  const driver=new Function('THREE','Math',grabFn(biomes,'trainDriver')+'\nreturn trainDriver;')(THREE,random);
  const update=driver(train,line,original.speed),frames=[];
  const spec={...original,start:sample*original.total};
  for(const delta of [0,...Array(1200).fill(1/60),0,.25,8,0,line.total/original.speed,0]) {
    update(delta);train.updateMatrixWorld(true);
    frames.push({delta,matrix:train.matrixWorld.toArray()});
  }
  fixtures.trainPrograms.push({bundle:'berlin_1_autumn',spec,frames});
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during capture: '+file);
const inputs={};
for(const file of ['tools/train_motion_capture.mjs','tools/train_references.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
if(digest(await readFile(join(root,worldPath)))!==digest(worldBytes))throw new Error('Seasonal train capture changed during replay');
inputs[worldPath]=digest(worldBytes.toString('utf8').replace(/\r\n?/g,'\n'));
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/train_motion.json'),{formatVersion:1,source:{inputs,sourceInputs},...fixtures});
console.log('TRAIN_MOTION_REFERENCES_PASS programs='+fixtures.trainPrograms.length);
