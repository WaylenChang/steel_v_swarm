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
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const update=PrologueIntroController.prototype.updateSceneState.toString();
const play=PrologueIntroController.prototype.play.toString();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[],rules={};
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[640,360],[320,568],[500,500]]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,update,play})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-crawl-viewport" style="width:320px;height:100px;flex:none"><div class="prologue-crawl-content"><section class="prologue-crawl-section" data-idx="0" style="height:200px"></section><section class="prologue-crawl-section" data-idx="1" style="height:160px"></section><section class="prologue-crawl-section" data-idx="2" style="height:220px"></section></div></div>';
      const viewport=document.querySelector('.prologue-crawl-viewport'),content=document.querySelector('.prologue-crawl-content');
      const style=getComputedStyle(viewport),v=viewport.getBoundingClientRect(),c=content.getBoundingClientRect();
      const insets={top:parseFloat(style.paddingTop),right:parseFloat(style.paddingRight),bottom:parseFloat(style.paddingBottom),left:parseFloat(style.paddingLeft)};
      const sections=[...content.children].map(section=>({top:section.offsetTop,height:section.offsetHeight}));
      const sectionGap=parseFloat(getComputedStyle(content.children[0]).marginBottom);
      let progress=0,index=-1;
      const prototype=new Function('calcCameraTransform',`return {${update}};`)((_camera,value)=>{progress=value;return '';});
      const context=Object.assign(Object.create(prototype),{viewport,content,scenes:[{camera:{}},{camera:{}},{camera:{}}],activeSceneIdx:0,
        setScene(value){index=value;this.activeSceneIdx=value;}});
      const frames=[];
      for(const requested of [0,10,50,179,190,400,10000]){
        viewport.scrollTop=requested;
        context.updateSceneState();
        frames.push({requested,scroll:viewport.scrollTop,index,progress});
      }
      const callbacks=[];
      const originalPlay=new Function('requestAnimationFrame','performance','bufferGameCache',`return function ${play};`)(
        callback=>{callbacks.push(callback);return callbacks.length;},{now:()=>1000},()=>new Promise(()=>{}));
      Object.assign(context,{root:{style:{},classList:{add(){},remove(){}}},isPrologue:false,destroyed:false,
        initDOM(){},renderStatus(){},activeSceneIdx:-1});
      originalPlay.call(context,1);
      const initial={scroll:viewport.scrollTop,index:context.activeSceneIdx};
      callbacks.shift()(1000);
      const jump={initial,after:{scroll:viewport.scrollTop,index:context.activeSceneIdx,progress}};
      return {insets,sectionGap,viewport:[viewport.clientWidth,viewport.clientHeight],scrollHeight:viewport.scrollHeight,
        content:[c.x-v.x,c.y-v.y,c.width,c.height],sections,frames,jump};
    },{css,update,play});
    const mode=width>height?'landscape':'portrait';
    if(rules[mode]&&JSON.stringify(rules[mode])!==JSON.stringify(sample.insets))throw new Error('Original crawl padding varies within '+mode);
    rules[mode]=sample.insets;
    programs.push({size:[width,height],...sample});
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_crawl_insets_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_crawl_insets.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_crawl_insets.json'),{...base,browser:browser.version(),programs});
console.log('CAMPAIGN_CRAWL_INSETS_CAPTURE_PASS programs='+programs.length);
