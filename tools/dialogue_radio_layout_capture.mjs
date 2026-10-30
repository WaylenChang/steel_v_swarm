import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const paths=['public/css/style.css','public/js/dialogue.js'],sourceInputs={};
for(const path of paths){
  const bytes=await readFile(join(source,path));sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original source changed: '+path);
}
const sourceJs=await readFile(join(source,paths[1]),'utf8');
for(const token of ['class="dlg-note"','class="dlg-row"','class="dlg-av dlg-av-l"','class="dlg-txt"','class="dlg-av dlg-av-r"'])
  if(!sourceJs.includes(token))throw new Error('Original radio markup changed: '+token);
const css=await readFile(join(source,paths[0]),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[320,568],[360,640],[500,500],[720,900],[721,900],[825,600],[826,600],[1024,768],[1440,900]]){
    await page.setViewportSize({width,height});
    for(const [noteHeight,rowHeight] of [[12,52],[18,80],[25,140]]){
      const state=await page.evaluate(({css,noteHeight,rowHeight})=>{
        document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
        document.body.innerHTML='<div class="dlg-layer"><div class="dlg-bar"><div class="dlg-note"></div><div class="dlg-row"></div></div></div>';
        const bar=document.querySelector('.dlg-bar'),note=document.querySelector('.dlg-note'),row=document.querySelector('.dlg-row');
        bar.style.animation='none';note.style.height=noteHeight+'px';row.style.height=rowHeight+'px';
        const b=bar.getBoundingClientRect(),n=note.getBoundingClientRect(),r=row.getBoundingClientRect();
        const s=getComputedStyle(bar),ns=getComputedStyle(note),rs=getComputedStyle(row);
        const av=document.createElement('img');av.className='dlg-av';row.append(av);
        const as=getComputedStyle(av);
        return {box:[b.x,b.y,b.width,b.height],note:[n.x-b.x,n.y-b.y,n.width,n.height],row:[r.x-b.x,r.y-b.y,r.width,r.height],
          padding:['left','top','right','bottom'].map(k=>parseFloat(s.getPropertyValue('padding-'+k))),
          border:['left','top','right','bottom'].map(k=>parseFloat(s.getPropertyValue('border-'+k+'-width'))),
          bottom:parseFloat(s.bottom),gap:parseFloat(ns.marginBottom),rowGap:parseFloat(rs.columnGap),avatar:parseFloat(as.width)};
      },{css,noteHeight,rowHeight});
      programs.push({viewport:[width,height],noteHeight,rowHeight,...state});
    }
  }
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Original source changed during capture: '+path);
const cssRules=css.match(/\.dlg-bar\s*\{[^}]*width:\s*min\(([\d.]+)px,\s*([\d.]+)vw\)/);
if(!cssRules)throw new Error('Unsupported original radio width rule');
const breakpoint=css.match(/@media\s*\(max-width:\s*([\d.]+)px\)\s*\{\s*\.dlg-bar\s*\{/);
if(!breakpoint)throw new Error('Unsupported original radio breakpoint');
const desktop=programs.find(p=>p.viewport[0]===721),mobile=programs.find(p=>p.viewport[0]===720);
const layoutUnits=[1,2,4,8,16,32,64,128,256].find(n=>programs.every(p=>[p.box[2],p.box[3]].every(x=>Number.isInteger(x*n))));
const rules={maxWidth:Number(cssRules[1]),viewportRatio:Number(cssRules[2])/100,layoutUnits,
  mobileMaxWidth:Number(breakpoint[1]),desktop:{padding:desktop.padding,border:desktop.border,bottom:desktop.bottom,gap:desktop.gap,rowGap:desktop.rowGap,avatar:desktop.avatar},
  mobile:{padding:mobile.padding,border:mobile.border,bottom:mobile.bottom,gap:mobile.gap,rowGap:mobile.rowGap,avatar:mobile.avatar}};
const inputs={};for(const path of ['tools/dialogue_radio_layout_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/dialogue_radio_layout.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/dialogue_radio_layout.json'),{...base,browser:browser.version(),programs});
console.log('DIALOGUE_RADIO_LAYOUT_CAPTURE_PASS programs='+programs.length);
