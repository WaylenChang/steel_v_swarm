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
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original cinematic input changed: '+path);
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['bindEvents','startLongPress','cancelLongPress'].map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const a={id:1,x:60,y:80},b={id:2,x:120,y:80},button={id:2,x:250,y:80};
const cases=[
  {name:'same-target-batched-release',steps:[{type:'touchStart',time:1000,points:[a]},{type:'touchStart',time:1050,points:[a,b]},{type:'touchEnd',time:1100,points:[]}]},
  {name:'same-target-separate-release',steps:[{type:'touchStart',time:1000,points:[a]},{type:'touchStart',time:1050,points:[a,b]},{type:'touchEnd',time:1100,points:[b]},{type:'touchEnd',time:1200,points:[]}]},
  {name:'separate-release-outside-window',steps:[{type:'touchStart',time:1000,points:[a]},{type:'touchStart',time:1050,points:[a,b]},{type:'touchEnd',time:1100,points:[b]},{type:'touchEnd',time:1450,points:[]}]},
  {name:'button-and-root-batched',steps:[{type:'touchStart',time:1000,points:[a]},{type:'touchStart',time:1050,points:[a,button]},{type:'touchEnd',time:1100,points:[]}]},
  {name:'ordinary-double-tap',steps:[{type:'touchStart',time:1000,points:[a]},{type:'touchEnd',time:1050,points:[]},{type:'touchStart',time:1100,points:[a]},{type:'touchEnd',time:1200,points:[]}]},
  {name:'batched-cancel',steps:[{type:'touchStart',time:1000,points:[a]},{type:'touchStart',time:1050,points:[a,b]},{type:'touchCancel',time:1100,points:[]}]},
];
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try{
  for(const item of cases){
    const page=await browser.newPage({viewport:{width:320,height:240},deviceScaleFactor:1,hasTouch:true,isMobile:true});
    await page.setContent('<div id="root" style="position:fixed;inset:0;touch-action:none"><button id="prologueFinishBtn" style="position:absolute;left:220px;top:40px;width:80px;height:80px">Finish</button></div>');
    await page.evaluate(methods=>{
      let now=0;
      const Controller=new Function('performance','requestAnimationFrame','cancelAnimationFrame',
        'return class {'+methods.join('\n')+'}')({now:()=>now},()=>1,()=>{});
      const root=document.querySelector('#root');
      const context=Object.assign(new Controller(),{root,viewport:null,holdIndicator:null,holdCircle:null,
        holdRaf:null,holdStart:0,lastTapTime:0,destroyed:false,skips:[],trySkip(reason){this.skips.push(reason);}});
      context.bindEvents();
      const events=[];
      for(const type of ['pointerdown','pointerup','pointercancel','touchstart','touchend','touchcancel'])
        window.addEventListener(type,event=>events.push({type,target:event.target.id,
          pointer:event.pointerId??null,changed:event.changedTouches?[...event.changedTouches].map(t=>t.identifier):[]}),true);
      window.setClock=value=>{now=value;};
      window.sample=()=>({holding:context.holdRaf!==null,lastTap:context.lastTapTime,skips:[...context.skips],events:events.splice(0)});
    },methods);
    const protocol=await page.context().newCDPSession(page);
    await protocol.send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:5});
    const frames=[];
    for(const step of item.steps){
      await page.evaluate(time=>window.setClock(time),step.time);
      await protocol.send('Input.dispatchTouchEvent',{type:step.type,touchPoints:step.points});
      frames.push({...step,...await page.evaluate(()=>window.sample())});
    }
    programs.push({name:item.name,frames});
    await page.close();
  }
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_touch_bundle_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_touch_bundle.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_TOUCH_BUNDLE_CAPTURE_PASS programs='+programs.length);
