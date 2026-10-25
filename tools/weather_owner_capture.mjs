import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const path='public/js/weatherVisuals.js';
const bytes=await readFile(join(source,path));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
if(provenance.inputs[path]!==digest(bytes))throw new Error('Original weather profile input changed');
const original=await import(pathToFileURL(join(source,path)).href);
const cases=[];
for(const strength of [0,.01,.5,1])for(const wind of [0,50,100]) {
  const dynamics={effectiveRain:strength,effectiveSnow:1-strength,effectiveSand:strength*.5,wind,windDir:[.6,-.8]};
  cases.push({dynamics,profiles:original.resolveWeatherVisuals(dynamics)});
}
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Weather owner capture requires the original Chromium runtime');
await mkdir(join(root,'artifacts/sol'),{recursive:true});
const previousDirectory=process.cwd(),executablePath=chromePath();
let browser,browserVersion,browserCases;
try {
  process.chdir(join(root,'artifacts/sol'));
  browser=await chromium.launch({headless:true,executablePath});
  browserVersion=browser.version();
  const page=await browser.newPage();
  browserCases=await page.evaluate(async({url,cases})=>{
    const original=await import(url);
    return cases.map(item=>({dynamics:item.dynamics,profiles:original.resolveWeatherVisuals(item.dynamics)}));
  },{url:'data:text/javascript;base64,'+bytes.toString('base64'),cases});
} finally {
  try {if(browser)await browser.close();}
  finally {process.chdir(previousDirectory);}
}
const tape=rows=>rows.map(item=>Object.fromEntries(['rain','snow','sand'].map(kind=>[kind,
  Object.fromEntries(Object.entries(item.profiles[kind]).map(([key,value])=>[key,Math.fround(value)]))])));
if(JSON.stringify(tape(cases))!==JSON.stringify(tape(browserCases)))throw new Error('Original browser/Node particle profile storage disagrees');
if(digest(await readFile(join(source,path)))!==digest(bytes))throw new Error('Source changed during weather capture');
const inputs={};
for(const file of ['tools/weather_owner_capture.mjs','tools/fixture_json.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/weather_owner.json'),{formatVersion:1,
  source:{inputs,sourceInputs:{[path]:digest(bytes)},runtime:{node:process.version,v8:process.versions.v8,chromium:browserVersion}},
  budgets:original.WEATHER_FX.particles,cases:browserCases});
console.log('WEATHER_OWNER_CAPTURE_PASS '+JSON.stringify({cases:browserCases.length}));
