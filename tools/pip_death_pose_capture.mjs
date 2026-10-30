import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/game.js','tools/audit_src.mjs']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original death-view input changed: '+path);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(game,'_renderDeathCam');
const start=method.indexOf('    if (src) {'),end=method.indexOf('\n\n    const r = this.renderer',start);
if(start<0||end<0)throw new Error('Missing original death-view camera branches');
const program=method.slice(start,end);
const tower=/cam\.position\.set\(m\.x, m\.y \+ \(src\.dimTop \|\| ([\d.]+)\) \+ ([\d.]+), m\.z\)/.exec(program);
const fallback=/_surf\(px, pz, Infinity\) \+ ([\d.]+)/.exec(program);
if(!tower||!fallback)throw new Error('Missing original death-view eye constants');
const rules={defaultTop:Number(tower[1]),sourceLift:Number(tower[2]),groundLift:Number(fallback[1])};
const points=[[12,5,-9],[1024,-1024,-2048],[.5,0,-.5],[-2048,2,2048]];
const tops=[null,0,14,23.1,-.125,0.0000001,'NaN'];
const grounds=[0,1.3,-20.25,0.0000001,4096.0002];
for(const point of points)if(!point.every(value=>Object.is(value,Math.fround(value))))
  throw new Error('Fixture positions must survive native vector storage');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let cases;
try{
  const page=await browser.newPage();
  cases=await page.evaluate(({program,points,tops,grounds})=>{
    const run=new Function('src','cam','ex','ez',program);
    const bits=(value,wide)=>{const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');};
    const cases=[];
    for(const mode of ['source','fallback'])for(const point of points)for(const parameter of mode==='source'?tops:grounds){
      const src=mode==='source'?{mesh:{position:{x:point[0],y:point[1],z:point[2]}},dimTop:parameter==='NaN'?NaN:parameter}:null;
      let eye=[],target=[],queries=[];
      const cam={position:{set:(...value)=>eye=value},up:{set(){}},lookAt:(...value)=>target=value};
      const context={pos:{x:point[0],z:point[2]},_surf:(...value)=>{queries.push(value);return parameter;}};
      run.call(context,src,cam,100,-100);
      cases.push({mode,point,parameter,eyeBits:eye.map(value=>bits(value,true)),eyeFloat32Bits:eye.map(value=>bits(value,false)),
        targetBits:target.map(value=>bits(value,true)),surfaceCalls:queries.length});
    }
    return cases;
  },{program,points,tops,grounds});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original death-view input changed during capture: '+path);
const inputs={};
for(const path of ['tools/pip_death_pose_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/pip_death_pose.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/pip_death_pose.json'),{...base,browser:browser.version(),cases});
console.log('PIP_DEATH_POSE_CAPTURE_PASS cases='+cases.length);
