import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/vfx.js','out/forest_review/three.module.js']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original fog geometry input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const vfx=(await readFile(join(source,'public/js/vfx.js'),'utf8')).replace(/\r\n?/g,'\n');
const start=vfx.indexOf('export function spawnFogVFX('),end=vfx.indexOf('\n}\n',start);
if(start<0||end<0)throw new Error('Missing original fog constructor');
const spawn=new Function('THREE',vfx.slice(start,end+3).replace('export function','return function'))(THREE);
const cases=[];
for(const radius of [10,35,60,35.000004])for(const ally of [false,true]) {
  const scene=new THREE.Scene(),effects=[];
  spawn(scene,effects,{x:12,z:-9,r:radius,dur:8,isAlly:ally});
  const group=effects[0].obj;group.updateMatrixWorld(true);
  const nodes=group.children.map(node=>{
    const geometry=node.geometry.toNonIndexed(),positions=geometry.getAttribute('position'),normal=geometry.getAttribute('normal');
    const vertices=[],normals=[];
    for(let index=0;index<positions.count;index++) {
      vertices.push(new THREE.Vector3().fromBufferAttribute(positions,index).applyMatrix4(node.matrix).toArray());
      normals.push(new THREE.Vector3().fromBufferAttribute(normal,index).transformDirection(node.matrix).toArray());
    }
    const row={vertices,normals,uv:[...geometry.getAttribute('uv').array],opacity:node.material.opacity,
      color:node.material.color.getHex(),side:node.material.side,transparent:node.material.transparent,depthWrite:node.material.depthWrite};
    geometry.dispose();return row;
  });
  cases.push({radius,ally,nodes});
  for(const node of group.children){node.geometry.dispose();node.material.dispose();}
  scene.clear();
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during fog capture: '+path);
const inputs={};
for(const path of ['tools/fog_geometry_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/fog_geometry.json'),{formatVersion:1,source:{inputs,sourceInputs},cases});
console.log('FOG_GEOMETRY_CAPTURE_PASS '+JSON.stringify({cases:cases.length}));
