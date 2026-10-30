import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const path='public/css/style.css',css=await readFile(join(source,path),'utf8');
if(digest(Buffer.from(css))!==provenance.inputs[path])throw new Error('Original stylesheet identity changed');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage();
  programs=await page.evaluate(css=>{
    const style=document.createElement('style');style.textContent=css;document.head.append(style);
    const result=[];
    for(const [channel,name] of [['fire','env-fog'],['weather','weather-fog']])
      for(const initial of [0,1])for(const time of [.02,.1])for(const flush of [false,true]){
        const el=document.createElement('div');el.className=name;el.style.opacity=String(initial);document.body.append(el);
        getComputedStyle(el).opacity;
        const target=1-initial;el.style.opacity=String(target);getComputedStyle(el).opacity;
        const animation=el.getAnimations().find(a=>a.transitionProperty==='opacity');
        if(!animation)throw new Error('Missing original opacity transition');
        animation.pause();animation.currentTime=time*1000;
        const before=Number(getComputedStyle(el).opacity);
        el.remove();
        let detachedAnimations=null;
        if(flush){getComputedStyle(el).opacity;detachedAnimations=el.getAnimations().length;}
        document.body.append(el);
        const after=Number(getComputedStyle(el).opacity),reattachedAnimations=el.getAnimations().length;
        result.push({channel,initial,target,time,flush,before,after,detachedAnimations,reattachedAnimations});el.remove();
      }
    style.remove();return result;
  },css);
}finally{await browser.close();}
if(digest(await readFile(join(source,path)))!==provenance.inputs[path])throw new Error('Original stylesheet changed during capture');
const inputs={};for(const file of ['tools/scope_detach_capture.mjs','tools/fixture_json.mjs'])
  inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/scope_detach.json'),{formatVersion:1,source:{inputs,sourceInputs:{[path]:provenance.inputs[path]}},browser:browser.version(),programs});
console.log('SCOPE_DETACH_CAPTURE_PASS programs='+programs.length);
