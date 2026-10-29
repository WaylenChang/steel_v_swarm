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
for(const path of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['setScene','play'].map(name=>PrologueIntroController.prototype[name].toString());
const scenes=['a','b','c'].map(id=>({id,title:id,badge:id,tag:id,paragraphs:[]}));
const colors=['rgba(220,40,20,.7)','rgba(20,190,60,.7)','rgba(40,60,220,.7)'];
const commands=[
  [[1,[0,.05,.2,.4]],[2,[0,.05,.1]],[1,[0,.02,.1,.4]]],
  [[2,[0,.1]],[1,[0,.03]],[2,[0,.02]],[0,[0]],[1,[0,.05,.4]]],
  [[1,[0,.1]],[1,[.2,.4]],[1,[.5]],[0,[0,.2,.4]]],
  [[1,[0]],[2,[0]],[0,[0,.001,.05,.4]]],
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules,layers,initial;
try{
  const page=await browser.newPage({viewport:{width:96,height:64},deviceScaleFactor:1});
  for(let programIndex=0;programIndex<commands.length;programIndex++){
    const config=await page.evaluate(({css,methods,scenes,colors})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css+
        '\nhtml,body{background:transparent!important}body::before{display:none!important}';
      document.body.innerHTML='<div id="root" class="prologue-screen" style="display:none"><div id="content"></div></div>';
      const root=document.getElementById('root'),content=document.getElementById('content');
      const prototype=new Function('performance','requestAnimationFrame','bufferGameCache',`return {${methods.join(',')}};`)(
        {now:()=>1000},()=>1,()=>new Promise(()=>{}));
      const context=Object.assign(Object.create(prototype),{root,content,scenes,activeSceneIdx:-1,
        dateTagEl:null,badgeEl:null,titleEl:null,viewport:{scrollTop:0},isPrologue:false,destroyed:false,
        initDOM(){content.innerHTML=scenes.map((_,index)=>`<section class="prologue-crawl-section" data-idx="${index}"></section>`).join('');},renderStatus(){}});
      context.play(0);
      const items=[...content.querySelectorAll('.prologue-crawl-section')],layers=[];
      for(let index=0;index<items.length;index++){
        const section=items[index];
        section.style.cssText='position:absolute;left:0;top:0;width:96px;height:64px;margin:0;padding:0;border:0';
        const base=document.createElement('div'),overlap=document.createElement('div');
        base.style.cssText=`position:absolute;inset:0;background:${colors[index]}`;
        overlap.style.cssText='position:absolute;left:16px;top:8px;width:56px;height:40px;background:rgba(255,255,255,.6)';
        section.replaceChildren(base,overlap);
        const rgba=element=>{const values=getComputedStyle(element).backgroundColor.match(/[\d.]+/g).map(Number);return [values[0]/255,values[1]/255,values[2]/255,values[3]??1];};
        layers.push([{rect:[0,0,96,64],rgba:rgba(base)},{rect:[16,8,56,40],rgba:rgba(overlap)}]);
      }
      const initial=items.map(item=>Number(getComputedStyle(item).opacity));
      const initialAnimations=items.map(item=>item.getAnimations().length);
      const baseRule=[...document.styleSheets[0].cssRules].find(rule=>rule.selectorText==='.prologue-crawl-section');
      const activeRule=[...document.styleSheets[0].cssRules].find(rule=>rule.selectorText==='.prologue-crawl-section.active');
      if(!baseRule||!activeRule||baseRule.style.transitionTimingFunction!=='ease')throw new Error('Unsupported original section transition');
      const duration=parseFloat(baseRule.style.transitionDuration),inactive=parseFloat(baseRule.style.opacity),active=parseFloat(activeRule.style.opacity);
      if(!Number.isFinite(duration)||!Number.isFinite(inactive)||!Number.isFinite(active))throw new Error('Invalid original section transition');
      const elapsed=new WeakMap();let animations=[],last=0;
      window.sectionHarness={select(index){
        context.setScene(index);last=0;
        animations=items.map(element=>{getComputedStyle(element).opacity;const animation=element.getAnimations()[0];if(animation)animation.pause();return animation;});
      },sample(time){
        const delta=time-last;last=time;
        for(const animation of animations)if(animation){const value=(elapsed.get(animation)??0)+delta*1000;animation.currentTime=value;elapsed.set(animation,value);}
        return {delta,opacity:items.map(element=>Number(getComputedStyle(element).opacity)),selected:items.map(element=>element.classList.contains('active'))};
      }};
      return {rules:{inactive,active,duration,curve:[.25,.1,.25,1]},initial,initialAnimations,layers};
    },{css,methods,scenes,colors});
    if(rules&&JSON.stringify(config.rules)!==JSON.stringify(rules))throw new Error('Original section rules changed across programs');
    rules=config.rules;layers=config.layers;
    const currentInitial={opacity:config.initial,animations:config.initialAnimations};
    if(initial&&JSON.stringify(currentInitial)!==JSON.stringify({opacity:initial.opacity,animations:initial.animations}))
      throw new Error('Original initial section state changed across programs');
    if(!initial)initial={...currentInitial,png:(await page.screenshot({omitBackground:true})).toString('base64')};
    const frames=[];
    for(const [index,samples]of commands[programIndex]){
      await page.evaluate(index=>window.sectionHarness.select(index),index);
      for(let sample=0;sample<samples.length;sample++){
        const state=await page.evaluate(time=>window.sectionHarness.sample(time),samples[sample]);
        const frame={index,select:sample===0,time:samples[sample],...state};
        if(programIndex===0)frame.png=(await page.screenshot({omitBackground:true})).toString('base64');
        frames.push(frame);
      }
    }
    programs.push({frames});
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_section_opacity_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_section_opacity.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_section_opacity.json'),{...base,browser:browser.version(),scenes,layers,initial,programs});
console.log('CAMPAIGN_SECTION_OPACITY_CAPTURE_PASS programs='+programs.length);
