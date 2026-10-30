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
const methods=['bindEvents','startLongPress','cancelLongPress','trySkip']
  .map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
const normal=[['down','left',1],['up','left',1],['down','left',2],['up','left',2]];
const overlap=[['down','left',1],['up','left',1],['down','left',2],['down','right',1],
  ['up','left',2],['up','right',1]];
const wheel=[['down','left',1],['up','left',1],['down','left',2],['wheel','',0],['up','left',2]];
try{
  for(const {name,ready,operations} of [{name:'pending',ready:false,operations:normal},
    {name:'ready',ready:true,operations:normal},{name:'overlap',ready:false,operations:overlap},
    {name:'wheel',ready:false,operations:wheel}]){
    const page=await browser.newPage({viewport:{width:320,height:240},deviceScaleFactor:1});
    await page.setContent('<div id="root" style="position:fixed;inset:0"></div>');
    await page.evaluate(({methods,ready})=>{
      const Controller=new Function('return class {'+methods.join('\n')+'}')();
      const root=document.querySelector('#root');
      const state={finished:0,warnings:0};
      const context=Object.assign(new Controller(),{root,viewport:null,holdIndicator:null,holdCircle:null,
        holdRaf:null,holdStart:0,lastTapTime:0,destroyed:false,isBufferComplete:ready,
        finish(){state.finished++;this.destroyed=true;},showBufferWarning(){state.warnings++;}});
      window.requestAnimationFrame=()=>1;
      window.cancelAnimationFrame=()=>{};
      context.bindEvents();
      const events=[];
      for(const type of ['pointerdown','pointerup','click','dblclick'])
        root.addEventListener(type,event=>events.push({type,detail:event.detail}));
      window.sample=()=>({holding:context.holdRaf!==null,finished:state.finished,warnings:state.warnings,events:events.splice(0)});
    },{methods,ready});
    await page.mouse.move(100,100);
    const frames=[];
    for(const [action,button,clickCount] of operations){
      if(action==='wheel')await page.mouse.wheel(0,120);
      else await page.mouse[action]({button,clickCount});
      frames.push({action,button,clickCount,...await page.evaluate(()=>window.sample())});
    }
    programs.push({name,ready,frames});
    await page.close();
  }
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_double_click_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_double_click.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_DOUBLE_CLICK_CAPTURE_PASS programs='+programs.length);
