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
for(const path of ['public/css/style.css','public/index.html']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original system bar input changed: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const html=await readFile(join(source,'public/index.html'),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const cases=[];let rules;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[16,24],[101,50],[320,75]]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,html,width,height})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      const original=new DOMParser().parseFromString(html,'text/html').querySelector('#prologueIntro .prologue-hud-top .sysbar');
      if(!original||!original.querySelector('#prologueDateTag'))throw new Error('Original system bar markup changed');
      document.body.innerHTML='<div class="prologue-screen"><div class="prologue-hud-top"></div></div>';
      document.querySelector('.prologue-hud-top').append(original.cloneNode(true));
      const override=document.createElement('style');
      override.textContent=`html,body,.prologue-screen { margin:0; width:${width}px; height:${height}px; background:rgb(66,100,130); }
        .prologue-hud-top { background:none; border:0; padding:0; }
        .prologue-hud-top .sysbar { width:${width}px; height:${height}px; padding:0; box-sizing:border-box; }
        .prologue-hud-top .sysbar > * { visibility:hidden; }`;
      document.head.append(override);
      const style=getComputedStyle(document.querySelector('.prologue-hud-top .sysbar'));
      const rgba=value=>{const match=value.match(/^rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)$/);
        if(!match)throw new Error('Unsupported system bar color: '+value);
        return match.slice(1,4).map(x=>Number(x)/255).concat(Number(match[4]));};
      const gradient=style.backgroundImage.match(/^linear-gradient\(rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\),\s*rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)\)$/);
      if(!gradient)throw new Error('Unsupported system bar gradient: '+style.backgroundImage);
      return {top:gradient.slice(1,4).map(x=>Number(x)/255).concat(Number(gradient[4])),
        bottom:gradient.slice(5,8).map(x=>Number(x)/255).concat(Number(gradient[8])),
        border:rgba(style.borderBottomColor),borderWidth:parseFloat(style.borderBottomWidth)};
    },{css,html,width,height});
    if(rules&&JSON.stringify(sample)!==JSON.stringify(rules))throw new Error('System bar styling varies');
    rules=sample;
    cases.push({size:[width,height],png:(await page.screenshot({type:'png'})).toString('base64')});
  }
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original system bar input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_sysbar_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_sysbar.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_sysbar.json'),{...base,browser:browser.version(),cases});
console.log('CAMPAIGN_SYSBAR_CAPTURE_PASS cases='+cases.length);
