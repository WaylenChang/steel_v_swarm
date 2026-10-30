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
for(const path of paths){const bytes=await readFile(join(source,path));sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original source changed: '+path);}
const script=await readFile(join(source,paths[1]),'utf8');
for(const token of ['class="dlg-av dlg-av-l"','class="dlg-txt"','class="dlg-av dlg-av-r"',"if (!id) { av.style.display = 'none'; continue; }"])
  if(!script.includes(token))throw new Error('Original radio markup changed: '+token);
const css=await readFile(join(source,paths[0]),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[360,640],[720,900],[721,900],[1440,900]]){
    await page.setViewportSize({width,height});
    for(const rowWidth of [160,240,400])for(const textHeight of [20,80])for(const right of [false,true]){
      const sample=await page.evaluate(({css,rowWidth,textHeight,right})=>{
        document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
        document.body.innerHTML='<div class="dlg-row"><div class="dlg-av dlg-av-l"></div><div class="dlg-txt"></div><div class="dlg-av dlg-av-r"></div></div>';
        const row=document.querySelector('.dlg-row'),left=row.children[0],text=row.children[1],rightAv=row.children[2];
        row.style.width=rowWidth+'px';row.style.height='80px';text.style.height=textHeight+'px';
        if(!right)rightAv.style.display='none';
        const base=row.getBoundingClientRect();
        const rect=node=>{const r=node.getBoundingClientRect();return [r.x-base.x,r.y-base.y,r.width,r.height];};
        return {row:[base.width,base.height],left:rect(left),text:rect(text),right:right?rect(rightAv):null,
          gap:parseFloat(getComputedStyle(row).columnGap),avatar:parseFloat(getComputedStyle(left).width)};
      },{css,rowWidth,textHeight,right});
      programs.push({viewport:[width,height],rowWidth,textHeight,hasRight:right,...sample});
    }
  }
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Source changed during capture: '+path);
const inputs={};for(const path of ['tools/dialogue_radio_grid_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/dialogue_radio_grid.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('DIALOGUE_RADIO_GRID_CAPTURE_PASS programs='+programs.length);
