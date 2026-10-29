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
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[640,360],[320,568],[500,500]]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,update})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      const sections=[30,50,70].map(height=>`<section class="prologue-crawl-section"><div class="pcs-chapter-mark"><div style="width:10px;height:20px"></div></div><div class="pcs-paras"><p style="height:${height}px;margin:0"></p></div></section>`).join('');
      document.body.innerHTML='<div class="prologue-crawl-viewport" style="width:320px;height:100px;flex:none;padding:0"><div class="prologue-crawl-content">'+sections+'<div style="height:40px;flex:none"></div></div></div>';
      const viewport=document.querySelector('.prologue-crawl-viewport'),content=document.querySelector('.prologue-crawl-content');
      const nodes=[...content.querySelectorAll('.prologue-crawl-section')],marker=nodes[0].querySelector('.pcs-chapter-mark'),style=getComputedStyle(marker);
      const rgba=value=>{const numbers=value.match(/[\d.]+/g)?.map(Number);if(!numbers||numbers.length<3)throw new Error('Unsupported marker border: '+value);return [numbers[0]/255,numbers[1]/255,numbers[2]/255,numbers[3]??1];};
      const rules={bottomPadding:parseFloat(style.paddingBottom),borderWidth:parseFloat(style.borderBottomWidth),
        marginBottom:parseFloat(style.marginBottom),borderStyle:style.borderBottomStyle,borderColor:rgba(style.borderBottomColor),gap:parseFloat(style.gap)};
      let progress=0,index=-1;
      const prototype=new Function('calcCameraTransform',`return {${update}};`)((_camera,value)=>{progress=value;return '';});
      const context=Object.assign(Object.create(prototype),{viewport,content,scenes:[{camera:{}},{camera:{}},{camera:{}}],activeSceneIdx:0,
        setScene(value){index=value;this.activeSceneIdx=value;}});
      const frames=[];
      for(const requested of [0,10,50,90,120,200,10000]){
        viewport.scrollTop=requested;
        context.updateSceneState();
        frames.push({requested,scroll:viewport.scrollTop,index,progress});
      }
      const scrollHeight=viewport.scrollHeight,endTop=content.lastElementChild.offsetTop;
      const geometry=nodes.map(section=>({top:section.offsetTop,height:section.offsetHeight,
          markerHeight:section.querySelector('.pcs-chapter-mark').offsetHeight,
          paragraphsTop:section.querySelector('.pcs-paras').offsetTop-section.offsetTop}));
      const empty=nodes[0].cloneNode(true);
      empty.querySelector('.pcs-paras').replaceChildren();
      content.append(empty);
      const emptySection={height:empty.offsetHeight,paragraphsTop:empty.querySelector('.pcs-paras').offsetTop-empty.offsetTop};
      return {rules,viewport:[viewport.clientWidth,viewport.clientHeight],scrollHeight,
        sections:geometry,endTop,frames,emptySection};
    },{css,update});
    if(rules&&JSON.stringify(rules)!==JSON.stringify(sample.rules))throw new Error('Original marker geometry varies by viewport');
    rules=sample.rules;
    programs.push({size:[width,height],...sample});
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_marker_geometry_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_marker_geometry.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_marker_geometry.json'),{...base,browser:browser.version(),programs});
console.log('CAMPAIGN_MARKER_GEOMETRY_CAPTURE_PASS programs='+programs.length);
