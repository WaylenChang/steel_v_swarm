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
for(const path of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const endingText=JSON.parse(await readFile(join(root,'data/campaign_ending.json'),'utf8')).rules;
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const update=PrologueIntroController.prototype.updateSceneState.toString();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[640,360],[320,568],[500,500]]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,update,endingText})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-crawl-viewport" style="width:320px;height:100px;flex:none;padding:0"><div class="prologue-crawl-content"><section class="prologue-crawl-section" style="height:200px;flex:none"></section><div class="prologue-crawl-end"><div class="pce-divider" style="height:20px"></div><p class="pce-note" style="height:20px"></p><button class="btn big steel-btn prologue-finish-btn" style="width:240px;height:40px;padding:0"></button></div></div></div>';
      const viewport=document.querySelector('.prologue-crawl-viewport'),content=document.querySelector('.prologue-crawl-content');
      const section=content.querySelector('section'),ending=content.querySelector('.prologue-crawl-end');
      const divider=ending.querySelector('.pce-divider'),note=ending.querySelector('.pce-note'),button=ending.querySelector('button');
      divider.textContent=endingText.divider;note.textContent=endingText.prologue.note;button.textContent=endingText.prologue.button;
      const endStyle=getComputedStyle(ending),dividerStyle=getComputedStyle(divider),noteStyle=getComputedStyle(note);
      const rules={padding:Object.fromEntries(['top','right','bottom','left'].map(side=>[side,parseFloat(endStyle.getPropertyValue('padding-'+side))])),
        dividerGap:parseFloat(dividerStyle.marginBottom),noteGap:parseFloat(noteStyle.marginBottom)};
      const box=node=>{const rect=node.getBoundingClientRect(),parent=ending.getBoundingClientRect();return {top:rect.top-parent.top,height:rect.height};};
      const geometry=()=>({height:ending.getBoundingClientRect().height,divider:box(divider),note:box(note),button:box(button),scrollHeight:viewport.scrollHeight});
      const inline=geometry();
      button.style.display='block';button.style.margin='0 auto';
      const controlled=geometry();
      let progress=0,index=-1;
      const prototype=new Function('calcCameraTransform',`return {${update}};`)((_camera,value)=>{progress=value;return '';});
      const context=Object.assign(Object.create(prototype),{viewport,content,scenes:[{camera:{}}],activeSceneIdx:0,
        setScene(value){index=value;this.activeSceneIdx=value;}});
      const frames=[];
      for(const requested of [0,50,150,200,250,10000]){
        viewport.scrollTop=requested;context.updateSceneState();
        frames.push({requested,scroll:viewport.scrollTop,index,progress});
      }
      return {rules,viewport:[viewport.clientWidth,viewport.clientHeight],section:{top:section.offsetTop,height:section.offsetHeight},
        endingTop:ending.offsetTop,inline,controlled,frames};
    },{css,update,endingText});
    if(rules&&JSON.stringify(rules)!==JSON.stringify(sample.rules))throw new Error('Original ending geometry varies by viewport');
    rules=sample.rules;
    programs.push({size:[width,height],...sample});
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_ending_geometry_capture.mjs','tools/fixture_json.mjs','data/campaign_ending.json'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_ending_geometry.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_ending_geometry.json'),{...base,browser:browser.version(),programs});
console.log('CAMPAIGN_ENDING_GEOMETRY_CAPTURE_PASS programs='+programs.length);
