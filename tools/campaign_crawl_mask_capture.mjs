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
for(const path of ['public/css/style.css','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const html=await readFile(join(source,'public/index.html'),'utf8');
if(!html.includes('class="prologue-crawl-viewport"'))throw new Error('Original cinematic crawl viewport changed');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let mask;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[96,64],[101,73],[320,100]])for(const enabled of [false,true]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,enabled})=>{
      document.head.innerHTML='<style></style>';
      document.head.firstChild.textContent=css+'\nhtml,body{margin:0!important;background:rgb(16,32,48)!important}body::before{display:none!important}';
      document.body.innerHTML='<div id="viewport" class="prologue-crawl-viewport"><div id="base"></div><div id="overlap"></div></div>';
      const viewport=document.getElementById('viewport'),base=document.getElementById('base'),overlap=document.getElementById('overlap');
      viewport.style.cssText='position:absolute;inset:0;width:100vw;height:100vh;flex:none;padding:0;overflow:hidden';
      base.style.cssText='position:absolute;inset:0;background:rgb(40,180,210)';
      overlap.style.cssText='position:absolute;left:10px;top:8px;width:40px;height:40px;background:rgba(220,80,60,.5)';
      const sourceMask=getComputedStyle(viewport).maskImage;
      if(!enabled){viewport.style.maskImage='none';viewport.style.webkitMaskImage='none';}
      const rgba=element=>{const values=getComputedStyle(element).backgroundColor.match(/[\d.]+/g).map(Number);return [values[0]/255,values[1]/255,values[2]/255,values[3]??1];};
      return {mask:sourceMask,layers:[{rect:[0,0,innerWidth,innerHeight],rgba:rgba(base)},{rect:[10,8,40,40],rgba:rgba(overlap)}]};
    },{css,enabled});
    if(mask&&mask!==sample.mask)throw new Error('Original crawl mask differs by viewport');
    mask=sample.mask;
    programs.push({size:[width,height],enabled,layers:sample.layers,png:(await page.screenshot()).toString('base64')});
  }
}finally{await browser.close();}
if(!mask||mask==='none')throw new Error('Missing original crawl mask');
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_crawl_mask_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_crawl_mask.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),mask,backdrop:[16/255,32/255,48/255,1],programs});
console.log('CAMPAIGN_CRAWL_MASK_CAPTURE_PASS programs='+programs.length);
