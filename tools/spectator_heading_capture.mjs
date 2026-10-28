import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_heading_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabConst,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(contents['public/js/game.js'],'_updateSpectator');
const start=method.indexOf('      this._specYaw = camAngleStep(');
const end=method.indexOf(';',start);
if(start<0||end<0)throw new Error('Missing original spectator heading branch');
const data=contents['public/js/data.js'];
const arrow=name=>{
  const pattern=name==='wrapPi'
    ? /^export const wrapPi = \(a\) => \{[\s\S]*?^\};/m
    : new RegExp('^export const '+name+' = [^\\n]+;','m');
  const match=pattern.exec(data);
  if(!match)throw new Error('Missing original camera helper: '+name);
  return match[0].replace(/^export /,'');
};
const program={heading:method.slice(start,end+1),rules:grabConst(data,'SPEC_CAM'),
  helpers:['frictionFPS','lerpFPS','wrapPi','camAngleStep'].map(arrow).join('\n')};
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let capture,runtime,rules;
try{
  const page=await browser.newPage();
  await page.goto('about:blank');
  ({capture,runtime,rules}=await page.evaluate(({program})=>{
    const rules=new Function(program.rules+'\nreturn SPEC_CAM;')();
    const camAngleStep=new Function(program.helpers+'\nreturn camAngleStep;')();
    const advance=new Function('camAngleStep','SPEC_CAM','tgt','view','dt',program.heading);
    const bits=value=>{
      const buffer=new ArrayBuffer(8),view=new DataView(buffer);
      view.setFloat64(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const capture=[];
    for(const mode of ['fpv','tps','orbit'])for(const initial of [-10000.25,-3.12,0,3.12,10000.25])
      for(const kind of ['missing','null','positive','negative'])for(const delta of [-.1,-1e-9,0,1/60,.1]){
        const target={};
        if(kind==='null')target.ry=null;
        if(kind==='positive')target.ry=.7;
        if(kind==='negative')target.ry=-3.12;
        const context={_specYaw:initial};
        advance.call(context,camAngleStep,rules,target,mode,delta);
        capture.push({mode,kind,initialBits:bits(initial),deltaBits:bits(delta),
          targetBits:typeof target.ry==='number'?bits(target.ry):null,resultBits:bits(context._specYaw)});
      }
    return {capture,runtime:{userAgent:navigator.userAgent},rules};
  },{program}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during spectator heading capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator heading generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_heading.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,rules,cases:capture});
console.log('SPECTATOR_HEADING_REFERENCES_PASS cases='+capture.length);
