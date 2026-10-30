import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/campaign_card_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/css/style.css','public/index.html']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const html=await readFile(join(source,'public/index.html'),'utf8');
for(const fragment of ['id="prologueNarrativeBox"','id="prologueBoxBadge"','id="prologueBoxTitle"','id="prologueCrawlViewport"','id="prologueDateTag"'])
  if(!html.includes(fragment))throw new Error('Original cinematic card markup changed: '+fragment);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const sizes=[[320,568],[568,320],[500,500],[375,812],[640,360],[720,450],[1024,768],
  [1440,900],[1920,1080],[1080,1920],[3840,2160],[1,1],[501,500],[377,376],[641,640]];
let rules;const cases=[],chromeRules={};
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of sizes){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,html})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-screen"><div class="prologue-hud-top"></div><div class="prologue-narrative-box" id="prologueNarrativeBox"><div class="prologue-box-header"><span class="prologue-box-badge" id="prologueBoxBadge"></span><h2 class="prologue-box-title" id="prologueBoxTitle"></h2></div><div class="prologue-crawl-viewport" id="prologueCrawlViewport"><div class="prologue-crawl-content" id="prologueCrawlContent"></div></div></div><div class="prologue-hud-bottom"></div></div>';
      const original=new DOMParser().parseFromString(html,'text/html');
      const originalBar=original.querySelector('#prologueIntro .prologue-hud-top .sysbar');
      if(!originalBar||!originalBar.querySelector('#prologueDateTag')||originalBar.children.length!==2)throw new Error('Original cinematic system bar changed');
      document.querySelector('.prologue-hud-top').append(originalBar.cloneNode(true));
      const media={},chrome={};
      for(const rule of document.styleSheets[0].cssRules){
        if(rule.selectorText==='.prologue-hud-top')chrome.top=rule.style;
        if(rule.selectorText==='.prologue-hud-bottom')chrome.bottom=rule.style;
        if(!rule.cssRules||!rule.conditionText)continue;
        const mode=rule.conditionText.includes('orientation: landscape')?'landscape':rule.conditionText.includes('orientation: portrait')?'portrait':null;
        if(!mode)continue;
        for(const child of rule.cssRules){
          if(child.selectorText==='.prologue-narrative-box')media[mode]=child.style;
          if(mode==='portrait'&&child.selectorText==='.prologue-hud-top')chrome.portraitTop=child.style;
          if(mode==='portrait'&&child.selectorText==='.prologue-hud-bottom')chrome.portraitBottom=child.style;
        }
      }
      if(!media.landscape||!media.portrait||!chrome.top||!chrome.bottom||!chrome.portraitTop||!chrome.portraitBottom)
        throw new Error('Missing original card or HUD orientation styles');
      const numbers=value=>[...value.matchAll(/([\d.]+)(px|vw|vh)/g)].map(match=>[Number(match[1]),match[2]]);
      const lw=numbers(media.landscape.width),lh=numbers(media.landscape.height),pw=numbers(media.portrait.width),ph=numbers(media.portrait.height);
      const lb=numbers(media.landscape.bottom),pb=numbers(media.portrait.bottom),pm=numbers(media.portrait.maxWidth);
      if(JSON.stringify(lw.map(x=>x[1]))!==JSON.stringify(['px','vw'])||JSON.stringify(lh.map(x=>x[1]))!==JSON.stringify(['px','vh'])
        ||JSON.stringify(pw.map(x=>x[1]).sort())!==JSON.stringify(['px','vw'])||JSON.stringify(ph.map(x=>x[1]))!==JSON.stringify(['px','vh'])
        ||!lb.length||!pb.length||!pm.length)throw new Error('Unsupported original cinematic card CSS: '+JSON.stringify({
          landscape:{width:media.landscape.width,height:media.landscape.height,bottom:media.landscape.bottom},
          portrait:{width:media.portrait.width,height:media.portrait.height,bottom:media.portrait.bottom,maxWidth:media.portrait.maxWidth}}));
      const box=document.getElementById('prologueNarrativeBox'),style=getComputedStyle(box),rect=box.getBoundingClientRect();
      const border=style.borderLeftColor.match(/^rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)$/);
      if(!border||['Top','Right','Bottom'].some(side=>style[`border${side}Color`]!==style.borderLeftColor
        ||style[`border${side}Width`]!==style.borderLeftWidth))throw new Error('Unsupported original card border');
      const borderColor=border.slice(1,4).map(value=>Number(value)/255).concat(Number(border[4]));
      const top=getComputedStyle(document.querySelector('.prologue-hud-top'));
      const bottom=getComputedStyle(document.querySelector('.prologue-hud-bottom'));
      const bar=document.querySelector('.prologue-hud-top .sysbar'),barStyle=getComputedStyle(bar),barRect=bar.getBoundingClientRect();
      if(barStyle.position!=='fixed'||barStyle.display!=='flex')throw new Error('Original cinematic system bar is not fixed flex layout');
      const dateStyle=getComputedStyle(bar.querySelector('#prologueDateTag'));
      const dateColor=dateStyle.color.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);
      if(!dateColor)throw new Error('Unsupported original cinematic date color: '+dateStyle.color);
      const systemBar={top:parseFloat(barStyle.top),left:parseFloat(barStyle.left),right:parseFloat(barStyle.right),
        paddingTop:parseFloat(barStyle.paddingTop),paddingBottom:parseFloat(barStyle.paddingBottom),
        paddingLeft:parseFloat(barStyle.paddingLeft),paddingRight:parseFloat(barStyle.paddingRight),borderBottom:parseFloat(barStyle.borderBottomWidth),
        archive:bar.firstElementChild.textContent.trim(),dateSize:parseFloat(dateStyle.fontSize),
        dateColor:dateColor.slice(1).map(value=>Number(value)/255).concat(1)};
      if(Object.entries(systemBar).some(([key,value])=>!['archive','dateColor'].includes(key)&&!Number.isFinite(value)))throw new Error('Unsupported original cinematic system bar');
      const chromeRule={topHorizontal:parseFloat(top.paddingRight),top:parseFloat(top.paddingTop),
        bottomHorizontal:parseFloat(bottom.paddingRight),bottom:parseFloat(bottom.paddingBottom),gap:parseFloat(bottom.gap)||0};
      if(Object.values(chromeRule).some(value=>!Number.isFinite(value)))throw new Error('Unsupported original HUD padding');
      return {rules:{landscape:{maxWidth:lw[0][0],widthRatio:lw[1][0]/100,maxHeight:lh[0][0],heightRatio:lh[1][0]/100,bottom:lb[0][0]},
        portrait:{widthMargin:pw.find(x=>x[1]==='px')[0],maxWidth:pm[0][0],maxHeight:ph[0][0],heightRatio:ph[1][0]/100,bottom:pb[0][0]},
        border:parseFloat(style.borderLeftWidth),borderColor,systemBar},chrome:chromeRule,rect:[rect.x,rect.y,rect.width,rect.height],
        systemBarRect:[barRect.x,barRect.y,barRect.width,barRect.height]};
    },{css,html});
    if(rules&&JSON.stringify(sample.rules)!==JSON.stringify(rules))throw new Error('Card rules vary across source viewports');
    rules=sample.rules;
    const mode=width>height?'landscape':'portrait';
    if(chromeRules[mode]&&JSON.stringify(chromeRules[mode])!==JSON.stringify(sample.chrome))throw new Error('HUD rules vary within '+mode);
    chromeRules[mode]=sample.chrome;
    cases.push({size:[width,height],rect:sample.rect,systemBarRect:sample.systemBarRect});
  }
}finally{await browser.close();}
const units=[1,2,4,8,16,32,64,128,256,512,1024].find(value=>cases.every(row=>row.rect.slice(2).every(number=>Math.abs(number*value-Math.round(number*value))<1e-7)));
if(!units)throw new Error('Cannot identify original card layout units');
rules.chrome=chromeRules;
rules.layoutUnits=units;
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during card capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Campaign card generator changed during capture');
const input={formatVersion:1,source:{inputs:{[generator]:generatorHash},sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_card.json'),input);
await writeFixtureJson(join(root,'tests/fixtures/campaign_card.json'),{...input,browser:browser.version(),cases});
console.log('CAMPAIGN_CARD_REFERENCES_PASS cases='+cases.length);
