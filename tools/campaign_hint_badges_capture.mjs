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
const programs=[];
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height,hintWidth] of [[320,568,280],[720,720,120],[1440,900,420]]){
    await page.setViewportSize({width,height});
    const states=await page.evaluate(({css,render,hintWidth})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-buffer-status"></div><div class="prologue-skip-hint"></div>';
      const status=document.querySelector('.prologue-buffer-status'),hint=document.querySelector('.prologue-skip-hint');
      hint.style.width=hintWidth+'px';
      const method=new Function('return {'+render+'};')().renderStatus;
      const rect=element=>{const r=element.getBoundingClientRect(),h=hint.getBoundingClientRect();return [r.x-h.x,r.y-h.y,r.width,r.height];};
      return [false,true,false,true].map(ready=>{
        method.call({statusEl:status,skipHintEl:hint,isBufferComplete:ready,bufferPercent:58});
        const style=getComputedStyle(hint);
        const badges=[...hint.querySelectorAll('.prologue-key-badge')].map(badge=>{
          const s=getComputedStyle(badge);
          return {text:badge.textContent,rect:rect(badge),background:s.backgroundColor,borderColor:s.borderColor,
            borderWidth:s.borderTopWidth,borderRadius:s.borderTopLeftRadius,padding:[s.paddingTop,s.paddingRight,s.paddingBottom,s.paddingLeft],color:s.color};
        });
        return {ready,text:hint.textContent,unlocked:hint.classList.contains('unlocked'),
          display:style.display,alignment:style.alignItems,gap:style.gap,letterSpacing:style.letterSpacing,
          height:hint.getBoundingClientRect().height,badges};
      });
    },{css,render,hintWidth});
    programs.push({size:[width,height],hintWidth,states});
  }
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original campaign input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_hint_badges_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_hint_badges.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_HINT_BADGES_CAPTURE_PASS programs='+programs.length);
