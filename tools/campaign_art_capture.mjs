import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['initDOM','setScene'].map(name=>PrologueIntroController.prototype[name].toString());
const scenes=['a','b','c'].map(id=>({id,title:id,badge:id,tag:id,paragraphs:[],camera:{},img:'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg"/%3E'}));
const colors=['rgba(220,40,20,.7)','rgba(20,190,60,.7)','rgba(40,60,220,.7)'];
const commands=[
  [[0,[0,.05,.2]],[1,[0,.05,.1]],[2,[0,.02,.1]],[0,[0,.05,.2,.9]]],
  [[2,[0,.1]],[1,[0,.03]],[2,[0,.02]],[0,[0]],[1,[0,.05,.9]]],
  [[1,[0,.1]],[1,[.2,.5,.9]],[1,[1]],[0,[0,.45,.9]]],
  [[0,[0,.9]],[2,[0,.45]],[0,[0,.45]],[2,[0,.45,.9]]],
  [[0,[0]],[1,[0]],[2,[0]],[0,[0,.001,.05,.9]]],
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules,layers;
try {
  const page=await browser.newPage({viewport:{width:96,height:64},deviceScaleFactor:1});
  for(let programIndex=0;programIndex<commands.length;programIndex++) {
    const config=await page.evaluate(({css,methods,scenes,colors})=>{
      document.head.innerHTML='<style></style>';
      document.head.firstChild.textContent=css+'\nhtml,body{background:transparent!important}body::before{display:none!important}';
      document.body.innerHTML='<div class="prologue-stage"><div class="prologue-scenes" id="prologueScenes"></div></div>';
      const prototype=new Function(`return {${methods.join(',')}};`)();
      const context=Object.assign(Object.create(prototype),{root:document.body,scenesContainer:document.getElementById('prologueScenes'),
        content:null,scenes,activeSceneIdx:-1,dateTagEl:null,badgeEl:null,titleEl:null});
      context.initDOM();
      const items=[...document.querySelectorAll('.prologue-scene-item')],layers=[];
      for(let index=0;index<items.length;index++) {
        const base=document.createElement('div'),overlap=document.createElement('div');
        base.style.cssText=`position:absolute;inset:0;background:${colors[index]}`;
        overlap.style.cssText='position:absolute;left:16px;top:8px;width:56px;height:40px;background:rgba(255,255,255,.6)';
        items[index].replaceChildren(base,overlap);
        const rgba=element=>{const values=getComputedStyle(element).backgroundColor.match(/[\d.]+/g).map(Number);return [values[0]/255,values[1]/255,values[2]/255,values[3]??1];};
        layers.push([{rect:[0,0,96,64],rgba:rgba(base)},{rect:[16,8,56,40],rgba:rgba(overlap)}]);
      }
      const style=getComputedStyle(items[0]),match=style.transitionTimingFunction.match(/^cubic-bezier\(([^)]+)\)$/);
      if(!match||items.length!==scenes.length)throw new Error('Unsupported original cinematic scene transition');
      const rules={duration:parseFloat(style.transitionDuration),curve:match[1].split(',').map(Number)};
      const elapsed=new WeakMap();let animations=[],last=0;
      window.artHarness={select(index){
        context.setScene(index);last=0;
        animations=items.map(element=>{getComputedStyle(element).opacity;const animation=element.getAnimations()[0];if(animation)animation.pause();return animation;});
      },sample(time){
        const delta=time-last;last=time;
        for(const animation of animations)if(animation){const value=(elapsed.get(animation)??0)+delta*1000;animation.currentTime=value;elapsed.set(animation,value);}
        return {delta,opacity:items.map(element=>Number(getComputedStyle(element).opacity)),order:items.map(element=>element.id)};
      }};
      return {rules,layers};
    },{css,methods,scenes,colors});
    rules=config.rules;layers=config.layers;
    const frames=[];
    for(const [index,samples]of commands[programIndex]) {
      await page.evaluate(index=>window.artHarness.select(index),index);
      for(let sample=0;sample<samples.length;sample++) {
        const state=await page.evaluate(time=>window.artHarness.sample(time),samples[sample]);
        const frame={index,select:sample===0,time:samples[sample],...state};
        if(programIndex===0)frame.png=(await page.screenshot({omitBackground:true})).toString('base64');
        frames.push(frame);
      }
    }
    programs.push({frames});
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during cinematic scene capture: '+file);
const file='tools/campaign_art_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'data/campaign_art.json'),{formatVersion:1,source:{inputs,sourceInputs},rules});
await writeFixtureJson(join(root,'tests/fixtures/campaign_art.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),rules,scenes,layers,programs});
console.log('CAMPAIGN_ART_REFERENCES_PASS programs='+programs.length+' frames='+programs.reduce((sum,item)=>sum+item.frames.length,0));
