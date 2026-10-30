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
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/css/style.css']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original cinematic input changed: '+path);
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['initDOM','bindEvents','startLongPress','cancelLongPress','trySkip']
  .map(name=>PrologueIntroController.prototype[name].toString());
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const cases=[
  {name:'mouse-pending',kind:'mouse',ready:false,steps:['down-button','up-button']},
  {name:'mouse-ready',kind:'mouse',ready:true,steps:['down-button','up-button']},
  {name:'mouse-release-outside',kind:'mouse',ready:false,steps:['down-button','move-outside','up-outside']},
  {name:'mouse-press-outside',kind:'mouse',ready:false,steps:['down-outside','move-button','up-button']},
  {name:'touch-pending',kind:'touch',ready:false,steps:['down-button','up-button']},
  {name:'touch-ready',kind:'touch',ready:true,steps:['down-button','up-button']},
  {name:'touch-cancel',kind:'touch',ready:false,steps:['down-button','cancel-button']},
  {name:'touch-release-outside',kind:'touch',ready:false,steps:['down-button','move-outside','up-outside']},
  {name:'touch-press-outside',kind:'touch',ready:false,steps:['down-outside','move-button','up-button']},
  {name:'touch-return-inside',kind:'touch',ready:false,steps:['down-button','move-outside','move-button','up-button']},
];
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try{
  for(const item of cases){
    const page=await browser.newPage({viewport:{width:360,height:240},deviceScaleFactor:1,hasTouch:true,isMobile:item.kind==='touch'});
    await page.setContent('<meta name="viewport" content="width=device-width, initial-scale=1"><div id="root" style="position:fixed;inset:0"><div id="viewport" class="prologue-crawl-viewport"><div id="content"></div></div></div>');
    await page.addStyleTag({content:css});
    await page.addStyleTag({content:'#viewport{position:absolute;inset:0;overflow:auto}#content{height:480px}#prologueFinishBtn{position:absolute;left:220px;top:80px;width:100px;height:50px}'});
    await page.evaluate(({methods,ready})=>{
      let now=1000;
      const Controller=new Function('document','window','performance','requestAnimationFrame','cancelAnimationFrame',
        'return class {'+methods.join('\n')+'}')(document,window,{now:()=>now},()=>1,()=>{});
      const controller=Object.assign(new Controller(),{root:document.querySelector('#root'),viewport:document.querySelector('#viewport'),
        content:document.querySelector('#content'),scenesContainer:null,scenes:[],options:{},isPrologue:true,
        holdIndicator:null,holdCircle:null,holdRaf:null,lastTapTime:0,destroyed:false,isBufferComplete:ready,
        finishes:0,warnings:0,finish(){this.finishes++;this.destroyed=true;},showBufferWarning(){this.warnings++;},updateSceneState(){}});
      controller.initDOM();
      const events=[];
      for(const type of ['pointerdown','pointerup','pointercancel','touchstart','touchmove','touchend','touchcancel','click'])
        window.addEventListener(type,event=>events.push({type,target:event.target.id}),true);
      window.setClock=value=>{now=value;};
      window.sample=()=>({finishes:controller.finishes,warnings:controller.warnings,holding:controller.holdRaf!==null,lastTap:controller.lastTapTime,events:events.splice(0)});
    },{methods,ready:item.ready});
    const protocol=await page.context().newCDPSession(page);
    if(item.kind==='touch')await protocol.send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:5});
    const frames=[];
    for(let i=0;i<item.steps.length;i++){
      const operation=item.steps[i],time=1000+i*100,inside=operation.endsWith('button');
      const point=inside?{x:270,y:105}:{x:40,y:40};
      await page.evaluate(value=>window.setClock(value),time);
      if(item.kind==='mouse'){
        const type=operation.startsWith('down')?'mousePressed':operation.startsWith('up')?'mouseReleased':'mouseMoved';
        await protocol.send('Input.dispatchMouseEvent',{type,...point,button:type==='mouseMoved'?'none':'left',buttons:type==='mouseReleased'?0:1,clickCount:type==='mouseMoved'?0:1});
      }else{
        const type=operation.startsWith('down')?'touchStart':operation.startsWith('up')?'touchEnd':operation.startsWith('cancel')?'touchCancel':'touchMove';
        await protocol.send('Input.dispatchTouchEvent',{type,touchPoints:type==='touchEnd'||type==='touchCancel'?[]:[{...point,id:1}]});
      }
      frames.push({operation,time,...await page.evaluate(()=>window.sample())});
    }
    programs.push({name:item.name,kind:item.kind,ready:item.ready,frames});
    await page.close();
  }
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_button_input_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_button_input.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_BUTTON_INPUT_CAPTURE_PASS programs='+programs.length);
