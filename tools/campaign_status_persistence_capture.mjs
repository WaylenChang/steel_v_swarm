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
for(const path of ['public/css/style.css','public/index.html','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original campaign input changed: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const html=await readFile(join(source,'public/index.html'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['renderStatus','showBufferWarning','play','finish'].map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage({viewport:{width:640,height:360},deviceScaleFactor:1});
  programs=await page.evaluate(({css,html,methods})=>{
    document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
    const programs=[];
    for(const scenario of ['no_warning','warning_persisted','warning_expired','warning_ready','warning_during_exit']){
      document.body.innerHTML='';
      const root=new DOMParser().parseFromString(html,'text/html').querySelector('#prologueIntro');
      document.body.append(root);
      const status=root.querySelector('#prologueBufferStatus'),hint=root.querySelector('#prologueSkipHint');
      // Isolate the persistent CSS classes from the separate animated pixel contract.
      status.style.transition='none';status.style.animation='none';
      const timers=[];
      const Controller=new Function('setTimeout','requestAnimationFrame','cancelAnimationFrame','bufferGameCache',
        'markPrologueSeen','performance','return class {'+methods.join('\n')+'}')(
        (callback,delay)=>{timers.push({callback,delay});return timers.length;},()=>1,()=>{},()=>new Promise(()=>{}),()=>{},
        {now:()=>1000});
      const make=isPrologue=>Object.assign(new Controller(),{root,statusEl:status,skipHintEl:hint,viewport:null,content:null,
        scenes:[{id:'scene'}],isPrologue,isBufferComplete:!isPrologue,bufferPercent:isPrologue?0:100,destroyed:false,
        animRaf:null,holdRaf:null,options:{},initDOM(){},setScene(){},cancelLongPress(){}});
      const records=[];
      const record=action=>records.push({action,visible:root.style.display!=='none',warning:status.classList.contains('flash-warn'),
        ready:status.classList.contains('ready'),status:status.textContent,hint:hint.textContent,
        color:getComputedStyle(status).color});
      const old=make(true);old.play();record('prologue');
      if(scenario!=='no_warning'){
        old.showBufferWarning();record('warning');
        if(scenario==='warning_ready'){old.isBufferComplete=true;old.bufferPercent=100;old.renderStatus();record('ready');}
        if(scenario==='warning_expired'){timers.find(item=>item.delay===1800).callback();record('expired');}
      }
      old.finish();record('finishing');
      if(scenario==='warning_during_exit'){
        timers.find(item=>item.delay===1800).callback();record('late_during_fade');
      }
      timers.find(item=>item.delay===650).callback();record('hidden');
      const chapter=make(false);chapter.play();record('chapter');
      if(scenario==='warning_persisted'||scenario==='warning_ready'){
        timers.find(item=>item.delay===1800).callback();record('late_warning');
      }
      chapter.finish();timers.filter(item=>item.delay===650).at(-1).callback();
      const replay=make(true);replay.play();record('replay');
      programs.push({scenario,records});
    }
    return programs;
  },{css,html,methods});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original campaign input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_status_persistence_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_status_persistence.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_STATUS_PERSISTENCE_CAPTURE_PASS programs='+programs.length);
