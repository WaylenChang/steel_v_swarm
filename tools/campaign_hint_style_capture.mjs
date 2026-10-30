import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original campaign input changed: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const render=PrologueIntroController.prototype.renderStatus.toString();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[320,568],[720,720],[1440,900]]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,render})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-buffer-status"></div><div class="prologue-skip-hint"></div>';
      const status=document.querySelector('.prologue-buffer-status'),hint=document.querySelector('.prologue-skip-hint');
      const method=new Function('return {'+render+'};')().renderStatus;
      const states=[];
      for(const ready of [false,true]){
        method.call({statusEl:status,skipHintEl:hint,isBufferComplete:ready,bufferPercent:58});
        const hintStyle=getComputedStyle(hint),statusStyle=getComputedStyle(status);
        const rgb=hintStyle.color.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);
        if(!rgb)throw new Error('Unsupported original hint color: '+hintStyle.color);
        states.push({ready,text:hint.textContent,color:rgb.slice(1).map(value=>Number(value)/255),
          fontSize:parseFloat(hintStyle.fontSize),statusFontSize:parseFloat(statusStyle.fontSize),
          badges:hint.querySelectorAll('.prologue-key-badge').length});
      }
      return states;
    },{css,render});
    const current={hintFontSize:sample[0].fontSize,statusFontSize:sample[0].statusFontSize,
      pendingColor:sample[0].color,readyColor:sample[1].color};
    if(rules&&JSON.stringify(rules)!==JSON.stringify(current))throw new Error('Original campaign hint style varies');
    rules=current;
    programs.push({size:[width,height],states:sample});
  }
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original campaign input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_hint_style_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_hint_style.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_hint_style.json'),{...base,browser:browser.version(),programs});
console.log('CAMPAIGN_HINT_STYLE_CAPTURE_PASS programs='+programs.length);
