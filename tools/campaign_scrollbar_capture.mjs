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
for(const path of ['public/css/style.css','public/js/prologue.js','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath(),ignoreDefaultArgs:['--hide-scrollbars']});
const programs=[];let style;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height,contentHeight,requested] of [
    [320,100,400,0],[320,100,400,150],[320,100,400,300],
    [96,64,256,0],[96,64,256,96],[96,64,256,192],
    [101,73,365,146],[96,24,400,0],[96,64,20,0],
    [320,100,150,0],[320,100,150,25],[320,100,150,50],
    [101,99,300,100],[96,12,400,0],[96,17,400,0],[96,18,400,0],[96,24,400,376],
  ]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,width,height,contentHeight,requested})=>{
      document.head.innerHTML='<style></style>';
      document.head.firstChild.textContent=css+'\nhtml,body{margin:0!important;background:rgb(20,60,90)!important}body::before{display:none!important}';
      document.body.innerHTML=`<div class="prologue-crawl-viewport" style="width:${width}px;height:${height}px;padding:0;background:rgb(20,60,90)"><div style="height:${contentHeight}px"></div></div>`;
      const viewport=document.querySelector('.prologue-crawl-viewport');
      viewport.style.setProperty('mask-image','none','important');
      viewport.style.setProperty('-webkit-mask-image','none','important');
      viewport.scrollTop=requested;
      const scrollbar=getComputedStyle(viewport,'::-webkit-scrollbar'),thumb=getComputedStyle(viewport,'::-webkit-scrollbar-thumb');
      return {style:{width:parseFloat(scrollbar.width),color:thumb.backgroundColor,radius:parseFloat(thumb.borderRadius)},
        clientWidth:viewport.clientWidth,scrollHeight:viewport.scrollHeight,scroll:viewport.scrollTop};
    },{css,width,height,contentHeight,requested});
    if(style&&JSON.stringify(style)!==JSON.stringify(sample.style))throw new Error('Original scrollbar style varies');
    style=sample.style;
    const png=(await page.screenshot()).toString('base64');
    const thumb=await page.evaluate(async({png,width,height})=>{
      const image=new Image();image.src='data:image/png;base64,'+png;await image.decode();
      const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
      const context=canvas.getContext('2d');context.drawImage(image,0,0);
      const pixels=context.getImageData(width-4,0,4,height).data,rows=[];
      for(let y=0;y<height;y++){
        let active=false;
        for(let x=0;x<4;x++){
          const i=(y*4+x)*4;
          if(pixels[i]!==20||pixels[i+1]!==60||pixels[i+2]!==90||pixels[i+3]!==255)active=true;
        }
        if(active)rows.push(y);
      }
      return rows.length?{top:rows[0],height:rows.at(-1)-rows[0]+1}:null;
    },{png,width,height});
    programs.push({size:[width,height],contentHeight,requested,...sample,thumb,png});
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_scrollbar_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_scrollbar.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),background:[20,60,90,255],style,programs});
console.log('CAMPAIGN_SCROLLBAR_CAPTURE_PASS programs='+programs.length);
