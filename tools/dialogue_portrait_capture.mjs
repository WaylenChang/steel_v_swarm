import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const paths=['public/css/style.css','public/js/dialogue.js'],sourceInputs={};
for(const path of paths){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original input changed: '+path);
}
const script=await readFile(join(source,paths[1]),'utf8');
if(!script.includes("for (const a of [avL, avR]) a?.classList.toggle('on', a === av);"))
  throw new Error('Original speaker endpoint update changed');
const css=await readFile(join(source,paths[0]),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let captured;
try{
  const page=await browser.newPage();
  captured=await page.evaluate(css=>{
    const style=document.createElement('style');style.textContent=css;document.head.append(style);
    const row=document.createElement('div');row.className='dlg-row';document.body.append(row);
    const probe=document.createElement('div');probe.className='dlg-av';row.append(probe);
    const inactive=Number(getComputedStyle(probe).opacity);
    const selected=document.createElement('div');selected.className='dlg-av on';row.append(selected);
    const active=Number(getComputedStyle(selected).opacity);
    const properties=getComputedStyle(probe).transitionProperty.split(',').map(s=>s.trim());
    const durations=getComputedStyle(probe).transitionDuration.split(',').map(s=>parseFloat(s));
    const timing=getComputedStyle(probe).transitionTimingFunction.split(/,\s*(?![^()]*\))/).map(s=>s.trim());
    const opacityIndex=properties.indexOf('opacity');
    if(opacityIndex<0||timing[opacityIndex]!=='ease-out')throw new Error('Unexpected original opacity transition');
    const duration=durations[opacityIndex];probe.remove();selected.remove();
    const programs=[];
    for(const initial of [false,true])for(const commands of [
      [[!initial,[0,.01,.04,.09,.18]],[initial,[0,.02,.09,.18]]],
      [[!initial,[0,.03,.07]],[initial,[0,.01,.03]],[!initial,[0,.03,.18]]],
      [[initial,[0,.05]],[!initial,[0,.03]],[!initial,[.05,.1]],[initial,[0,.01,.18]]],
      [[!initial,[0]],[initial,[0,.03]],[!initial,[0,.18]]]
    ]){
      const p=document.createElement('div');p.className='dlg-av'+(initial?' on':'');row.append(p);
      const initialOpacity=Number(getComputedStyle(p).opacity),frames=[];let previous=null;
      for(const [on,samples] of commands){
        p.classList.toggle('on',on);getComputedStyle(p).opacity;
        const animation=p.getAnimations().find(a=>a.transitionProperty==='opacity');
        if(animation)animation.pause();
        for(const time of samples){
          if(animation)animation.currentTime=time*1000;
          frames.push({on,time,newTransition:animation!==previous,
            duration:animation?animation.effect.getComputedTiming().duration/1000:0,
            opacity:Number(getComputedStyle(p).opacity)});
          previous=animation;
        }
      }
      programs.push({initial,initialOpacity,frames});p.remove();
    }
    row.remove();style.remove();
    return {rules:{active,inactive,duration},programs};
  },css);
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Input changed during capture: '+path);
const inputs={};
for(const path of ['tools/dialogue_portrait_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules:captured.rules};
await writeFixtureJson(join(root,'data/dialogue_portrait.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/dialogue_portrait.json'),{...base,browser:browser.version(),programs:captured.programs});
console.log('DIALOGUE_PORTRAIT_CAPTURE_PASS programs='+captured.programs.length);
