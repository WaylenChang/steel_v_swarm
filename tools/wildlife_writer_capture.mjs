import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/wildlifeRender.js','public/js/wildlife.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs[file]!==digest(bytes))throw new Error('Original wildlife writer input changed: '+file);
  sourceInputs[file]=digest(bytes);
}
const original=async file=>(await readFile(join(source,file),'utf8')).replace(/\r\n?/g,'\n');
const render=await original('public/js/wildlifeRender.js'),wildlife=await original('public/js/wildlife.js');
const {grabFn,grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const constants={};
for(const name of ['FLOCK','FISH','CAT','DOG']) {
  const declaration=wildlife.match(new RegExp('export const '+name+' = \\{[\\s\\S]*?\\n\\};'))?.[0];
  if(!declaration)throw new Error('Missing original wildlife spec: '+name);
  constants[name]=new Function(declaration.replace('export ','')+'\nreturn '+name+';')();
}
const helpers=['curveAt','wildlifeHeading','wingAngle','tailAngle'].map(name=>grabFn(wildlife,name)).join('\n');
const body=grabBlock(render,'const write = (t, dyn) =>');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Wildlife writer qualification requires original Chromium');
await mkdir(join(root,'artifacts/sol'),{recursive:true});
const previousDirectory=process.cwd(),executablePath=chromePath();
let browser,browserVersion,cases;
try {
  process.chdir(join(root,'artifacts/sol'));
  browser=await chromium.launch({headless:true,executablePath});browserVersion=browser.version();
  const page=await browser.newPage();
  cases=await page.evaluate(async({moduleUrl,constants,helpers,body})=>{
    const THREE=await import(moduleUrl),output=[];
    for(const [species,key]of Object.entries({bird:'FLOCK',fish:'FISH',cat:'CAT',dog:'DOG'}))
      for(const mode of ['dry','wet','missing'])for(const activity of [0,.5,1]) {
        // Explicit state/limb probes isolate the original writer; construction, geometry and integration are outside this capture.
        const spec=constants[key],pos=new Float32Array([0,20,0,9,-1,1,12,2,2]);
        const vel=new Float32Array([1,.2,2,0,0,0,.5,.1,-.25]);
        const st={spec,pos,vel,pts:new Float32Array([0,20,0,10,20,0,10,20,10,0,20,10]),
          n:4,len:40,count:3,t:0,spd:new Float32Array([1,1,1]),off:new Float32Array([0,.25,.5]),wing:new Float32Array([.125,.5,.75])};
        const geometry=new THREE.BufferGeometry(),material=new THREE.MeshBasicMaterial();
        const make=()=>new THREE.InstancedMesh(geometry,material,3),mesh=make();
        const parts=[{wing:1,p:[1,.2,0]},{leg:-1,p:[-.3,-.4,.2]},{tail:true,p:[0,0,-1]}];
        const limbs=parts.map(part=>({part,pivot:new THREE.Vector3(...part.p),rest:new THREE.Quaternion(),mesh:make()}));
        const probe=(x,z)=>mode==='wet'?-4:mode==='missing'&&x>0?NaN:10;
        const scope={batches:[{species,animals:[0,1,2].map(i=>({st,i})),body:mesh,limbs}],probe,
          bounds:{minX:-10,maxX:10,minZ:-10,maxZ:10},waterY:0,wetAt:()=>mode==='wet',validAt:()=>mode!=='wet',
          root:new THREE.Matrix4(),matrix:new THREE.Matrix4(),joint:new THREE.Matrix4(),position:new THREE.Vector3(),
          rotation:new THREE.Quaternion(),size:new THREE.Vector3(),local:new THREE.Quaternion(),direction:new THREE.Vector3(),
          forward:new THREE.Vector3(0,0,1),heading:[0,0,1],axisX:new THREE.Vector3(1,0,0),axisY:new THREE.Vector3(0,1,0),axisZ:new THREE.Vector3(0,0,1),unitScale:new THREE.Vector3(1,1,1)};
        const functions=new Function('FLOCK',helpers+'\nreturn {wildlifeHeading,wingAngle,tailAngle};')(constants.FLOCK);
        Object.assign(scope,functions);
        const write=new Function(...Object.keys(scope),'return (t,dyn)=>'+body)(...Object.values(scope));
        write(1.25,{activity});
        output.push({species,mode,activity,now:1.25,spec,
          state:{spec,n:st.n,len:st.len,count:3,t:0,pts:[...st.pts],pos:[...pos],vel:[...vel],spd:[...st.spd],off:[...st.off],wing:[...st.wing]},
          bounds:scope.bounds,parts,matrices:[mesh,...limbs.map(limb=>limb.mesh)].map(node=>[...node.instanceMatrix.array])});
        geometry.dispose();material.dispose();
      }
    return output;
  },{moduleUrl:'data:text/javascript;base64,'+(await readFile(join(source,'out/forest_review/three.module.js'))).toString('base64'),constants,helpers,body});
} finally {
  try {if(browser)await browser.close();}finally {process.chdir(previousDirectory);}
}
for(const [file,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during wildlife writer capture');
const inputs={};
for(const file of ['tools/wildlife_writer_capture.mjs','tools/fixture_json.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/wildlife_writer.json'),{formatVersion:1,source:{inputs,sourceInputs,runtime:{chromium:browserVersion}},cases});
console.log('WILDLIFE_WRITER_CAPTURE_PASS '+JSON.stringify({cases:cases.length}));
