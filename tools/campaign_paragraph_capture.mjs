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
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/css/style.css','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const {CHAPTER_SCENES}=await import(pathToFileURL(join(source,'public/js/chapterScenes.js')).href);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const css=await readFile(join(source,'public/css/style.css'),'utf8');
globalThis.document={getElementById:()=>({addEventListener(){}})};
const inputs=[['prologue',PROLOGUE_SCENES],['steel',CHAPTER_SCENES.ch1.STEEL],['swarm',CHAPTER_SCENES.ch1.SWARM]];
const markup=inputs.map(([kind,scenes])=>{
  const content={innerHTML:''};
  const controller=Object.assign(Object.create(PrologueIntroController.prototype),{
    scenes,scenesContainer:null,content,isPrologue:kind==='prologue',options:{},bindEvents(){}});
  controller.initDOM();
  return {kind,html:content.innerHTML};
});
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[],gaps={};
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const entry of markup){
    let sections;
    for(const [width,height] of [[640,360],[320,568],[500,500],[1024,768]]){
      await page.setViewportSize({width,height});
      const sample=await page.evaluate(({css,html})=>{
        document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
        document.body.innerHTML='<div class="prologue-screen"><div class="prologue-crawl-content"></div></div>';
        document.querySelector('.prologue-crawl-content').innerHTML=html;
        const rows=[...document.querySelectorAll('.prologue-crawl-section')];
        const paragraphs=rows.map(row=>({id:row.id.replace(/^prologue-crawl-/,''),paragraphs:[...row.querySelectorAll('.pcs-paras > p')].map(p=>p.textContent)}));
        const nonLast=document.querySelector('.pcs-paras > p:not(:last-child)');
        const last=document.querySelector('.pcs-paras > p:last-child');
        return {sections:paragraphs,gap:nonLast?parseFloat(getComputedStyle(nonLast).marginBottom):null,
          lastGap:last?parseFloat(getComputedStyle(last).marginBottom):null};
      },{css,html:entry.html});
      if(sections&&JSON.stringify(sections)!==JSON.stringify(sample.sections))throw new Error('Original paragraph text varies by viewport');
      sections=sample.sections;
      if(sample.lastGap!==0)throw new Error('Original last paragraph retains a bottom margin');
      if(sample.gap!==null){
        const mode=width>height?'landscape':'portrait';
        if(gaps[mode]!==undefined&&gaps[mode]!==sample.gap)throw new Error('Original paragraph margin varies within '+mode);
        gaps[mode]=sample.gap;
      }
    }
    programs.push({kind:entry.kind,sections});
  }
}finally{await browser.close();}
if(!Number.isFinite(gaps.landscape)||!Number.isFinite(gaps.portrait))throw new Error('Missing original paragraph margins');
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const captureInputs={};
for(const path of ['tools/campaign_paragraph_capture.mjs','tools/fixture_json.mjs'])
  captureInputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs:captureInputs,sourceInputs},rules:{landscapeGap:gaps.landscape,portraitGap:gaps.portrait}};
await writeFixtureJson(join(root,'data/campaign_paragraph.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_paragraph.json'),{...base,browser:browser.version(),programs});
console.log('CAMPAIGN_PARAGRAPH_CAPTURE_PASS programs='+programs.length);
