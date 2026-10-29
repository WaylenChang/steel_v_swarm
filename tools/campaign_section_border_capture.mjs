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
for(const path of ['public/css/style.css','public/js/prologue.js']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let style;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const width of [96,101,320,319,641]){
    const height=24;
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(css=>{
      document.head.innerHTML='<style></style>';
      document.head.firstChild.textContent=css+'\nhtml,body{margin:0!important;background:rgb(5,7,10)!important}body::before{display:none!important}';
      document.body.innerHTML='<section class="prologue-crawl-section active" style="width:100vw;height:24px;margin:0;padding:0"></section>';
      const section=document.querySelector('section'),computed=getComputedStyle(section);
      return {width:parseFloat(computed.borderBottomWidth),style:computed.borderBottomStyle,color:computed.borderBottomColor};
    },css);
    if(style&&JSON.stringify(style)!==JSON.stringify(sample))throw new Error('Original section border style varies');
    style=sample;
    const png=await page.screenshot();
    const row=await page.evaluate(async({encoded,width,height})=>{
      const image=new Image();image.src='data:image/png;base64,'+encoded;await image.decode();
      const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
      const context=canvas.getContext('2d');context.drawImage(image,0,0);
      const data=context.getImageData(0,height-1,width,1).data;
      return Array.from({length:width},(_,index)=>[data[index*4],data[index*4+1],data[index*4+2],data[index*4+3]]);
    },{encoded:png.toString('base64'),width,height});
    const runs=[];
    for(const pixel of row){
      const active=JSON.stringify(pixel)!==JSON.stringify([5,7,10,255]);
      const last=runs.at(-1);
      if(last&&last.active===active)last.length++;
      else runs.push({active,length:1});
    }
    programs.push({size:[width,height],runs,sample:row.slice(0,32),png:png.toString('base64')});
  }
}finally{await browser.close();}
if(style?.style!=='dashed'||style.width!==1)throw new Error('Unsupported original section border');
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_section_border_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_section_border.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),style,background:[5,7,10,255],programs});
console.log('CAMPAIGN_SECTION_BORDER_CAPTURE_PASS programs='+programs.length);
