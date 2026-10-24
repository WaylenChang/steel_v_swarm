import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const text=(await readFile(join(source,'public/js/prologue.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const functions=['easeInOutQuad','isLandscape','calcCameraTransform'].map(name=>grabFn(text,name)).join('\n');
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const scenes=PROLOGUE_SCENES.slice(0,3);
const initialSections=[{top:10,height:200},{top:234,height:160},{top:418,height:220}];
const changedSections=[{top:10,height:50},{top:84,height:310},{top:418,height:220}];
const frame=time=>({type:'frame',time,delta:.016});
const cases=[
  Array.from({length:400},(_,index)=>frame(1000+(index+1)*100)),
  [173,174,185,186,187,197,198,357,358,369,370,371,381,382,602,603].map((value,index)=>({type:'scroll',time:1100+index,value})),
  [{type:'wheel',time:1000},{type:'geometry',time:1100,sections:changedSections},frame(1200),frame(4200),frame(4200.001),frame(4300)],
  [{type:'scroll',time:1100,value:100000},{type:'geometry',time:1200,sections:[{top:10,height:200},{top:234,height:160},{top:418,height:900}]},frame(1300)],
  [{type:'scroll',time:1100,value:186},{type:'geometry',time:1200,sections:[{top:10,height:200},{top:222,height:0},{top:246,height:220}]},frame(1300),{type:'scroll',time:1400,value:187}],
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try {
  for(const landscape of [true,false])for(const operations of cases) {
    const page=await browser.newPage({viewport:landscape?{width:1000,height:500}:{width:500,height:1000},deviceScaleFactor:1});
    const program=await page.evaluate(({css,functions,controller,scenes,initialSections,operations,landscape})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div id="prologueIntro"><div id="prologueCrawlViewport" class="prologue-crawl-viewport" style="width:320px;height:100px;flex:none"><div style="height:1000px"></div></div></div>';
      let now=1000,serial=0;const callbacks=new Map();
      const Controller=new Function('performance','requestAnimationFrame','cancelAnimationFrame',`${functions}\nreturn (${controller});`)(
        {now:()=>now},callback=>{const id=++serial;callbacks.set(id,callback);return id;},id=>callbacks.delete(id));
      const context=new Controller({isPrologue:false,scenes});
      const targets=scenes.map(()=>({scale:1,x:0,y:0}));
      const setScene=context.setScene;
      context.setScene=function(index,transform){
        setScene.call(this,index,transform);
        if(transform){const match=transform.match(/translate3d\(([-\d.]+)%, ([-\d.]+)%, 0\) scale\(([\d.]+)\)/);
          if(!match)throw new Error('Unsupported original camera target');
          targets[index]={x:Number(match[1]),y:Number(match[2]),scale:Number(match[3])};}
      };
      context.play();context.bindEvents();
      let sections=initialSections.map(value=>({offsetTop:value.top,offsetHeight:value.height,classList:{toggle(){}}}));
      context.content={querySelectorAll:()=>sections};
      context.updateSceneState();
      const viewport=context.viewport,geometry={height:viewport.clientHeight,scrollHeight:viewport.scrollHeight,width:viewport.clientWidth,sections:initialSections};
      const frames=[];
      for(const operation of operations) {
        now=operation.time;
        if(operation.type==='frame'){const pending=[...callbacks];callbacks.clear();for(const [,callback]of pending)callback(now);}
        if(operation.type==='wheel')viewport.dispatchEvent(new WheelEvent('wheel'));
        if(operation.type==='geometry')sections=operation.sections.map(value=>({offsetTop:value.top,offsetHeight:value.height,classList:{toggle(){}}}));
        if(operation.type==='scroll'){const before=viewport.scrollTop;viewport.scrollTop=operation.value;
          if(viewport.scrollTop!==before)viewport.dispatchEvent(new Event('scroll'));}
        frames.push({operation,scroll:viewport.scrollTop,active:context.activeSceneIdx,targets:targets.map(value=>({...value}))});
      }
      return {landscape,geometry,frames};
    },{css,functions,controller:PrologueIntroController.toString(),scenes,initialSections,operations,landscape});
    programs.push(program);await page.close();
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during cinematic delivery capture: '+file);
const file='tools/campaign_delivery_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/campaign_delivery.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),scenes,programs});
console.log('CAMPAIGN_DELIVERY_REFERENCES_PASS programs='+programs.length+' frames='+programs.reduce((sum,item)=>sum+item.frames.length,0));
