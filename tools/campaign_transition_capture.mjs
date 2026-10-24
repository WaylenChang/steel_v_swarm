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
const methods=['finish','cancelLongPress'].map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let rules,frames;const rasters=[];
const width=96,height=64,background='#142841';
const layers=[{rect:[0,0,96,64],color:'#05070a'},{rect:[5,8,56,36],color:'rgba(255,255,255,.5)'},
  {rect:[30,20,55,36],color:'rgba(30,120,240,.75)'},{rect:[48,4,20,52],color:'rgba(240,80,20,.4)'}];
try {
  const page=await browser.newPage({viewport:{width,height},deviceScaleFactor:1});
  const result=await page.evaluate(({css,methods,layers,background})=>{
    document.head.innerHTML='<style></style>';
    document.head.firstChild.textContent=css+'\nhtml,body{background:transparent!important}body::before{display:none!important}';
    const behind=document.createElement('div');behind.style.cssText=`position:fixed;inset:0;background:${background}`;
    const root=document.createElement('div');root.className='prologue-screen';
    for(const layer of layers) {
      const element=document.createElement('div'),[left,top,width,height]=layer.rect;
      element.style.cssText=`position:absolute;left:${left}px;top:${top}px;width:${width}px;height:${height}px;background:${layer.color}`;
      root.append(element);
    }
    document.body.replaceChildren(behind,root);
    const resolvedLayers=layers.map((layer,index)=>{
      const match=getComputedStyle(root.children[index]).backgroundColor.match(/[\d.]+/g).map(Number);
      return {...layer,rgba:[match[0]/255,match[1]/255,match[2]/255,match[3]??1]};
    });
    const style=getComputedStyle(root),match=style.transitionTimingFunction.match(/^cubic-bezier\(([^)]+)\)$/);
    if(!match||style.opacity!=='1')throw new Error('Unsupported original cinematic exit style');
    const rules={exit:{duration:parseFloat(style.transitionDuration),curve:match[1].split(',').map(Number)}};
    let timer=null,completed=0;
    const prototype=new Function('setTimeout',`return {${methods.join(',')}};`)((fn,msec)=>{timer={fn,msec};return 1;});
    const context=Object.assign(Object.create(prototype),{root,destroyed:false,animRaf:null,holdRaf:null,
      holdIndicator:null,holdCircle:null,isPrologue:false,options:{onFinished(){completed++;}}});
    context.finish();context.finish();
    getComputedStyle(root).opacity;
    const animation=root.getAnimations()[0];
    if(!animation||!timer)throw new Error('Original finish must schedule a CSS fade and completion');
    animation.pause();
    const frames=[];
    for(const time of [0,.001,.01,.04,.1,.2,.35,.5,.6,.649999,.65]) {
      animation.currentTime=time*1000;
      const opacity=Number(getComputedStyle(root).opacity);
      if(time*1000>=timer.msec&&completed===0)timer.fn();
      frames.push({time,opacity,visible:root.style.display!=='none',completed});
    }
    return {rules,frames,layers:resolvedLayers,completionMsec:timer.msec};
  },{css,methods,layers,background});
  rules=result.rules;frames=result.frames;
  for(let index=0;index<layers.length;index++)layers[index].rgba=result.layers[index].rgba;
  if(result.completionMsec!==rules.exit.duration*1000)throw new Error('Original cinematic fade/timer duration mismatch');
  for(const time of [0,.01,.04,.1,.2,.35,.5,.6]) {
    await page.evaluate(({css,layers,background,time})=>{
      document.head.firstChild.textContent=css+'\nhtml,body{background:transparent!important}body::before{display:none!important}';
      const behind=document.createElement('div');behind.style.cssText=`position:fixed;inset:0;background:${background}`;
      const root=document.createElement('div');root.className='prologue-screen';
      for(const layer of layers) {
        const element=document.createElement('div'),[left,top,width,height]=layer.rect;
        element.style.cssText=`position:absolute;left:${left}px;top:${top}px;width:${width}px;height:${height}px;background:${layer.color}`;
        root.append(element);
      }
      document.body.replaceChildren(behind,root);getComputedStyle(root).opacity;
      root.classList.add('prologue-fadeout');getComputedStyle(root).opacity;
      const animation=root.getAnimations()[0];if(!animation)throw new Error('Missing original cinematic raster fade');
      animation.pause();animation.currentTime=time*1000;
    },{css,layers,background,time});
    rasters.push({time,png:(await page.screenshot({omitBackground:true})).toString('base64')});
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during cinematic transition capture: '+file);
const file='tools/campaign_transition_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'data/campaign_transition.json'),{formatVersion:1,source:{inputs,sourceInputs},rules});
await writeFixtureJson(join(root,'tests/fixtures/campaign_transition.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),rules,frames,
  composition:{width,height,background,layers,rasters}});
console.log('CAMPAIGN_TRANSITION_REFERENCES_PASS frames='+frames.length+' rasters='+rasters.length);
