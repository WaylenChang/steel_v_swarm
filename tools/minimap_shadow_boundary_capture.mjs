import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const paths=['public/js/game.js','tools/audit_src.mjs'],sourceInputs={};
for(const path of paths){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original source changed: '+path);
}
const game=(await readFile(join(source,paths[0]),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(game,'_mmShadows');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let cases;
try{
  const page=await browser.newPage();
  cases=await page.evaluate(method=>{
    const Client=new Function(`return class { ${method} }`)();
    const x=Math.fround(0.100296),z=Math.fround(1.200152);
    const radius=Math.sqrt(x*x+z*z);
    const values=[
      {name:'no-blockers',point:[0,0],sight:100,blockers:[]},
      {name:'inside-hypot-boundary',point:[0,0],sight:100,blockers:[{x,z,r:radius}]},
      {name:'inside',point:[0,0],sight:100,blockers:[{x:1,z:0,r:1}]},
      {name:'ordinary',point:[0,0],sight:100,blockers:[{x:12,z:5,r:2}]},
      {name:'outside-range',point:[0,0],sight:100,blockers:[{x:102,z:0,r:2}]},
      {name:'too-small',point:[0,0],sight:100,blockers:[{x:10,z:0,r:.49}]},
      {name:'translated',point:[10,-5],sight:100,blockers:[{x:22,z:0,r:2}]},
    ];
    return values.map(value=>{
      const client=new Client();client._blockersNear=()=>value.blockers;
      return {...value,shadows:client._mmShadows(...value.point,value.sight)};
    });
  },method);
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Source changed during capture: '+path);
const inputs={};
for(const path of ['tools/minimap_shadow_boundary_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/minimap_shadow_boundary.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),cases});
console.log('MINIMAP_SHADOW_BOUNDARY_CAPTURE_PASS cases='+cases.length);
