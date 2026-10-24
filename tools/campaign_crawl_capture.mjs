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
const programs=[],cases=[];
for(const rate of [120,60,40,30,20,15,10])cases.push(Array.from({length:120},(_,index)=>({type:'frame',time:1000+(index+1)*1000/rate,delta:1/rate})));
cases.push([1000,1001,1010,1050,1200,2200,2210].map(time=>({type:'frame',time,delta:.016})));
cases.push([{type:'wheel',time:1000},...[1001,4199.999,4200,4200.001,4300].map(time=>({type:'frame',time,delta:.016}))]);
cases.push([{type:'scroll',time:1000,value:20.5},...[1016,1032,1048].map(time=>({type:'frame',time,delta:.5}))]);
cases.push([{type:'scroll',time:1000,value:100000},...[1100,1200,1300].map(time=>({type:'frame',time,delta:.5}))]);
cases.push([1024.999,1049.999,1075].map(time=>({type:'frame',time,delta:.016})));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  for(const deviceScaleFactor of [1,1.25,1.5,2])for(const operations of cases) {
    const page=await browser.newPage({viewport:{width:400,height:300},deviceScaleFactor});
    const program=await page.evaluate(({css,controller,operations})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div id="prologueIntro"><div id="prologueCrawlViewport" class="prologue-crawl-viewport" style="width:320px;height:100px;flex:none"><div style="height:500px"></div></div></div>';
      let now=1000,serial=0;const callbacks=new Map();
      const Controller=new Function('performance','requestAnimationFrame','cancelAnimationFrame',`return (${controller});`)(
        {now:()=>now},callback=>{const id=++serial;callbacks.set(id,callback);return id;},id=>callbacks.delete(id));
      const context=new Controller({isPrologue:false,scenes:[{id:'probe',title:'probe',tag:'probe',badge:'probe'}]});
      context.play();context.bindEvents();
      const viewport=context.viewport,geometry={height:viewport.clientHeight,scrollHeight:viewport.scrollHeight,width:viewport.clientWidth};
      const frames=[];
      for(const operation of operations) {
        now=operation.time;
        if(operation.type==='frame') {const pending=[...callbacks];callbacks.clear();for(const [,callback]of pending)callback(now);}
        if(operation.type==='wheel')viewport.dispatchEvent(new WheelEvent('wheel'));
        if(operation.type==='scroll')viewport.scrollTop=operation.value;
        frames.push({operation,scroll:viewport.scrollTop,lastFrame:context.lastFrameTime,pauseUntil:context.userScrollPauseUntil});
      }
      context.destroyed=true;callbacks.clear();
      const replay=new Controller({isPrologue:false,scenes:[{id:'probe',title:'probe',tag:'probe',badge:'probe'}]});
      replay.play();
      return {geometry,frames,replay:{scroll:viewport.scrollTop,lastFrame:replay.lastFrameTime}};
    },{css,controller:PrologueIntroController.toString(),operations});
    programs.push({...program,deviceScaleFactor});await page.close();
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during crawl capture: '+file);
const file='tools/campaign_crawl_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/campaign_crawl.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_CRAWL_REFERENCES_PASS programs='+programs.length+' frames='+programs.reduce((sum,item)=>sum+item.frames.length,0));
