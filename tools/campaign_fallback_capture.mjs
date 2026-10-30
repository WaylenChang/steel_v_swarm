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
for(const path of ['public/js/prologue.js','public/css/style.css']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const init=PrologueIntroController.prototype.initDOM.toString();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const cases=[];let textures;
try{
  const page=await browser.newPage({viewport:{width:64,height:64},deviceScaleFactor:1});
  textures=await page.evaluate(()=>{
    const canvas=document.createElement('canvas');canvas.width=32;canvas.height=32;
    const ctx=canvas.getContext('2d');
    ctx.fillStyle='rgb(17,175,220)';ctx.fillRect(0,0,32,32);
    const fallback=canvas.toDataURL();
    ctx.clearRect(0,0,32,32);ctx.fillStyle='rgba(224,32,16,0.5)';ctx.fillRect(0,0,16,32);
    ctx.fillStyle='rgb(70,210,45)';ctx.fillRect(24,0,8,32);
    return {primary:canvas.toDataURL(),fallback};
  });
  const programs=[
    {name:'both',primary:'primary',fallback:'fallback'},
    {name:'same',primary:'primary',fallback:'primary'},
    {name:'primary_missing',primary:'missing',fallback:'fallback'},
    {name:'fallback_missing',primary:'primary',fallback:'missing'},
    {name:'no_fallback',primary:'primary',fallback:''},
    {name:'both_missing',primary:'missing',fallback:'missing'},
  ];
  for(const program of programs)for(const size of [32,64]){
    await page.setViewportSize({width:size,height:size});
    const info=await page.evaluate(async ({css,init,textures,program,size})=>{
      document.head.innerHTML='<style></style>';
      document.head.firstChild.textContent=css+`\nhtml,body{margin:0;background:rgb(12,24,36)!important;overflow:hidden}
        body::before{display:none!important}.prologue-stage,.prologue-scenes{position:absolute;inset:0!important;transform:none!important}
        .prologue-stage{background:rgb(12,24,36)!important}
        .prologue-scene-item{opacity:1!important;transition:none!important}.prologue-bg-blur{display:none!important}
        .prologue-fg-frame{position:absolute;inset:0!important;width:${size}px!important;height:${size}px!important;max-width:none!important;aspect-ratio:auto!important;transform:none!important;border:0!important;box-shadow:none!important}
        .prologue-fg-art{inset:0!important;transform:none!important;transition:none!important}`;
      document.body.innerHTML='<div class="prologue-stage"><div class="prologue-scenes"></div></div>';
      const urls={...textures,missing:'data:image/png;base64,AA=='};
      await Promise.all(Object.values(urls).map(url=>new Promise(resolve=>{const image=new Image();image.onload=image.onerror=resolve;image.src=url;})));
      const prototype=new Function('return {'+init+'};')();
      const scene={id:'probe',img:urls[program.primary]};
      if(program.fallback)scene.fallbackImg=urls[program.fallback];
      const context=Object.assign(Object.create(prototype),{scenes:[scene],scenesContainer:document.querySelector('.prologue-scenes'),content:null});
      context.initDOM();
      const art=document.querySelector('.prologue-fg-art');
      const background=document.querySelector('.prologue-bg-blur');
      await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
      return {foreground:art.style.backgroundImage,backdrop:background.style.backgroundImage};
    },{css,init,textures,program,size});
    if(info.foreground!==info.backdrop)throw new Error('Original art layers no longer share image order');
    const layerCount=[...info.foreground.matchAll(/url\(/g)].length;
    if(layerCount!==(program.fallback?2:1))throw new Error('Original fallback layer count changed: '+program.name);
    cases.push({...program,size,layerCount,png:(await page.screenshot()).toString('base64')});
  }
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_fallback_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_fallback.json'),{formatVersion:1,source:{inputs,sourceInputs},
  browser:browser.version(),textures:Object.fromEntries(Object.entries(textures).map(([key,value])=>[key,value.split(',')[1]])),cases});
console.log('CAMPAIGN_FALLBACK_CAPTURE_PASS cases='+cases.length);
