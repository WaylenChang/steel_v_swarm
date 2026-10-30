import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const contents={},sourceInputs={};
for(const path of ['public/js/game.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original minimap input changed: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const draw=grabMethod(contents['public/js/game.js'],'_drawMinimap');
const start=draw.indexOf('    const label = '),end=draw.lastIndexOf('}');
if(start<0||end<start)throw new Error('Original minimap label callback changed');
const label=draw.slice(start,end);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const cases=[];let runtime;
try{
  const page=await browser.newPage({viewport:{width:250,height:220},deviceScaleFactor:1});
  await page.setContent('<style>html,body{margin:0;background:rgb(40,80,120)}canvas{display:block}</style><canvas width="250" height="220"></canvas>');
  runtime=await page.evaluate(()=>({language:navigator.language,deviceScaleFactor:devicePixelRatio}));
  for(const [mode,width] of [['full',1200],['near',0],['near',.5],['near',139.5],['near',679.9],['near',10000.5]]){
    const metrics=await page.evaluate(({mode,width,label})=>{
      const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
      ctx.fillStyle='rgb(40,80,120)';ctx.fillRect(0,0,canvas.width,canvas.height);
      const originalFillText=ctx.fillText,fillText=originalFillText.bind(ctx);let rendered;
      ctx.fillText=(text,x,y)=>{rendered={text,x,y,font:ctx.font,baseline:ctx.textBaseline,align:ctx.textAlign,
        textWidth:ctx.measureText(text).width};fillText(text,x,y);};
      new Function('ctx','w','h','v',label).call({mmMode:mode},ctx,canvas.width,canvas.height,{x0:0,x1:width});
      ctx.fillText=originalFillText;
      return rendered;
    },{mode,width,label});
    if(!metrics)throw new Error('Original minimap label was not drawn');
    cases.push({mode,width,...metrics,png:(await page.locator('canvas').screenshot()).toString('base64')});
  }
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original minimap input changed during capture: '+path);
const inputs={};
for(const path of ['tools/minimap_label_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/minimap_label.json'),{formatVersion:1,source:{inputs,sourceInputs},
  browser:browser.version(),runtime,size:[250,220],background:[40,80,120],cases});
console.log('MINIMAP_LABEL_CAPTURE_PASS cases='+cases.length);
