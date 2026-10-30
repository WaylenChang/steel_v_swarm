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
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original minimap input changed: '+path);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const init=grabMethod(game,'_initMinimap');
const draw=grabMethod(game,'_drawMinimap');
const initial=init.match(/this\._mmLast = 0;[\s\S]*?this\._mmWarmUntil = performance\.now\(\) \/ 1000 \+ 3;/)?.[0];
const gate=draw.match(/const mmGate = [\s\S]*?this\._mmLast = now;/)?.[0];
if(!initial||!gate)throw new Error('Original minimap clock code changed');
const cases=[
  {name:'warm_boundary',init:100000.9,frames:[102800.1,103000.4,103000.95,103200.1]},
  {name:'fractional_gate',init:90000,frames:[500000.9,500200.95,500400.94,500400.96]},
  {name:'early_warmup',init:0.4,frames:[999.9,1000.1,1999.9,2000.2,3000.39,3000.41]},
  {name:'large_epoch',init:10000000.7,frames:[10004000.2,10004200.1,10004200.25]},
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage();
  programs=await page.evaluate(({initial,gate,cases})=>{
    const configure=new Function('performance',initial);
    const advance=new Function('now',gate+'\nreturn true;');
    const bits=value=>{
      const buffer=new ArrayBuffer(8);new DataView(buffer).setFloat64(0,value,true);
      return Array.from(new Uint8Array(buffer),byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    return cases.map(sample=>{
      const state={};configure.call(state,{now:()=>sample.init});
      const warmUntil=state._mmWarmUntil;
      const frames=sample.frames.map(ms=>{
        const due=advance.call(state,ms/1000)===true;
        return {ms,msBits:bits(ms),due,last:state._mmLast,lastBits:bits(state._mmLast)};
      });
      return {name:sample.name,init:sample.init,initBits:bits(sample.init),warmUntil,warmUntilBits:bits(warmUntil),frames};
    });
  },{initial,gate,cases});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original minimap input changed during capture: '+path);
const inputs={};
for(const path of ['tools/minimap_cadence_clock_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/minimap_cadence_clock.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('MINIMAP_CADENCE_CLOCK_CAPTURE_PASS programs='+programs.length);
