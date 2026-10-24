import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const cssPath='public/css/style.css',css=await readFile(join(source,cssPath),'utf8');
if(digest(Buffer.from(css))!==provenance.inputs[cssPath])throw new Error('Original stylesheet identity changed');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath(),ignoreDefaultArgs:['--hide-scrollbars']});
const programs=[];
let rules;
try {
  const page=await browser.newPage({deviceScaleFactor:1});
  await page.route('**/*',route=>route.abort());
  for(const viewport of [{width:360,height:640},{width:720,height:900},{width:721,height:900},
    {width:1440,height:900},{width:721,height:503},{width:721,height:641},{width:721,height:32}]) {
    await page.setViewportSize(viewport);
    for(const heights of [[],[40],[40,80,200,40],[500]]) {
      await page.setContent('<!doctype html><html><head></head><body></body></html>');
      await page.addStyleTag({content:css});
      const state=await page.evaluate(heights=>{
        // Controlled minimum-height rows isolate original CSS boxes from font advances.
        const body=document.createElement('div');body.className='dlg-scene-body';body.style.width='240px';
        const art=document.createElement('img');art.className='dlg-art dlg-art-r';
        art.src='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="300" height="600"/>');
        body.appendChild(art);
        const script=document.createElement('div');script.className='dlg-script';body.appendChild(script);
        for(const height of heights){const row=document.createElement('div');row.className='dlg-say';row.style.minHeight=height+'px';script.appendChild(row);}
        document.body.appendChild(body);
        const style=getComputedStyle(script),portrait=getComputedStyle(art),rect=body.getBoundingClientRect();
        const relative=node=>{const r=node.getBoundingClientRect();return [r.x-rect.x,r.y-rect.y,r.width,r.height];};
        return {body:relative(body),script:relative(script),rows:[...script.children].map(relative),
          clientWidth:script.clientWidth,clientHeight:script.clientHeight,scrollHeight:script.scrollHeight,
          padding:[style.paddingLeft,style.paddingTop,style.paddingRight,style.paddingBottom].map(parseFloat),
          gap:parseFloat(style.gap),maxHeight:parseFloat(style.maxHeight),artVisible:portrait.display!=='none',
          artWidth:parseFloat(portrait.width),artOpacity:parseFloat(portrait.opacity),
          background:getComputedStyle(body).backgroundColor,borderRadius:parseFloat(getComputedStyle(body).borderRadius)};
      },heights);
      if(viewport.height===900&&!rules)rules={padding:state.padding,gap:state.gap,maxHeightRatio:state.maxHeight/viewport.height,
        artWidth:state.artWidth,artOpacity:state.artOpacity};
      programs.push({viewport,width:240,heights,state});
    }
  }
} finally {await browser.close();}
rules.scrollbarWidth=Math.max(...programs.map(p=>p.state.script[2]-p.state.clientWidth));
rules.artMaxHiddenWidth=Math.max(...programs.filter(p=>!p.state.artVisible).map(p=>p.viewport.width));
rules.layoutUnits=[1,2,4,8,16,32,64,128,256].find(unit=>programs.every(p=>p.state.body.every(n=>Number.isInteger(n*unit))));
const color=programs[0].state.background.match(/[\d.]+/g).map(Number);
rules.background=[...color.slice(0,3).map(n=>n/255),color[3]];rules.borderRadius=programs[0].state.borderRadius;
const tool='tools/dialogue_body_capture.mjs';
if(digest(await readFile(join(source,cssPath)))!==provenance.inputs[cssPath])throw new Error('Original stylesheet changed during capture');
const identity={inputs:{[tool]:digest((await readFile(join(root,tool),'utf8')).replace(/\r\n?/g,'\n'))},sourceInputs:{[cssPath]:provenance.inputs[cssPath]}};
await writeFixtureJson(join(root,'data/dialogue_body.json'),{formatVersion:1,source:identity,rules});
await writeFixtureJson(join(root,'tests/fixtures/dialogue_body.json'),{formatVersion:1,source:identity,rules,programs});
console.log('DIALOGUE_BODY_CAPTURE_PASS programs='+programs.length);
