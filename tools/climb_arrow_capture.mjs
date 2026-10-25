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
for(const file of ['public/js/climb.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs[file]!==digest(bytes))throw new Error('Original climb arrow source changed: '+file);
  sourceInputs[file]=digest(bytes);
}
const original=(await readFile(join(source,'public/js/climb.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const declaration=/export const CLIMB_ARROW = (\{[\s\S]*?\n\});/.exec(original);
if(!declaration)throw new Error('Missing original climb arrow declarations');
const rules=new Function('return ('+declaration[1]+');')(),body=grabFn(original,'buildClimbArrows');
const minimum=/const sc = ([\d.]+) \+ ([\d.]+)/.exec(body);
if(!minimum)throw new Error('Missing original arrow endpoint scale');
const build=new Function('THREE','CLIMB_ARROW','UNIT','markShared',body+'\nreturn buildClimbArrows;')(THREE,rules,{},value=>value);
// Explicit route probes invoke only the source presentation constructor, not the authority planner.
const route=(x,z,nx,nz)=>({x,z,nx,nz,y0:2.5,y1:22.75});
const cases=[];
for(const routes of [[],[route(0,0,1,0)],[route(-15,27,0,-1),route(31,-9,.6,.8)]]) {
  const group=new THREE.Group();build(group,routes);
  const geometry=group.children[0]?.geometry;
  const snapshot=()=>group.children.map(mesh=>[...mesh.instanceMatrix.array]);
  const initial=snapshot(),frames=[];
  for(const delta of [0,.016,.25,4,0,100000.12345,.125]) {
    group.userData.update?.(delta);
    frames.push({delta,matrices:snapshot()});
  }
  cases.push({routes,geometry:geometry?{positions:[...geometry.attributes.position.array],indices:[...geometry.index.array]}:null,initial,frames});
  for(const mesh of group.children)mesh.material.dispose();
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during arrow capture: '+file);
const inputs={};
for(const file of ['tools/climb_arrow_capture.mjs','tools/fixture_json.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/climb_arrows.json'),{formatVersion:1,source:{inputs,sourceInputs},
  rules:{...rules,scaleMinimum:Number(minimum[1]),scaleRange:Number(minimum[2])},cases});
console.log('CLIMB_ARROW_CAPTURE_PASS '+JSON.stringify({cases:cases.length}));
