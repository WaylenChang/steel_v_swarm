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
for(const path of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original campaign input changed: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['renderStatus','showBufferWarning'].map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let captured;
try{
  const page=await browser.newPage({viewport:{width:640,height:360},deviceScaleFactor:1});
  captured=await page.evaluate(async ({css,methods})=>{
    document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
    const rgb=value=>{
      const match=value.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);
      if(!match)throw new Error('Unsupported original status color: '+value);
      return match.slice(1).map(Number);
    };
    const colours={};
    for(const [name,classes] of [['pending',''],['ready','ready'],['warning','flash-warn']]){
      const probe=document.createElement('div');
      probe.className='prologue-buffer-status '+classes;
      probe.style.transition='none';probe.style.animation='none';document.body.append(probe);
      colours[name]=rgb(getComputedStyle(probe).color);probe.remove();
    }
    const probe=document.createElement('div');probe.className='prologue-buffer-status';document.body.append(probe);
    const style=getComputedStyle(probe);
    const duration=parseFloat(style.transitionDuration);
    const timing=style.transitionTimingFunction;
    probe.remove();
    if(timing!=='ease'||duration!==.3)throw new Error('Unsupported original status transition');
    const rules={colors:Object.fromEntries(Object.entries(colours).map(([key,value])=>[key,value.map(channel=>channel/255)])),
      duration,curve:[.25,.1,.25,1]};
    const programs=[];
    for(const mode of ['ready','warning','warning_progress','reverse','same_target','double_reverse']){
      document.body.innerHTML='<div class="prologue-buffer-status"></div><div class="prologue-skip-hint"></div>';
      const status=document.querySelector('.prologue-buffer-status'),hint=document.querySelector('.prologue-skip-hint');
      const callbacks=[];
      const Controller=new Function('setTimeout','return class {'+methods.join('\n')+'}')(callback=>callbacks.push(callback));
      const controller=Object.assign(new Controller(),{statusEl:status,skipHintEl:hint,isBufferComplete:false,bufferPercent:58,destroyed:false});
      controller.renderStatus();getComputedStyle(status).color;
      if(mode==='ready'){controller.isBufferComplete=true;controller.renderStatus();}
      else controller.showBufferWarning();
      await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);
      let transition=status.getAnimations().find(animation=>animation.transitionProperty==='color');
      if(!transition)throw new Error('Missing original status color transition: '+mode);
      transition.pause();
      const at=ms=>{
        transition.currentTime=ms;
        const child=status.querySelector('.prologue-warn-tag, .prologue-check');
        return {ms,color:rgb(getComputedStyle(status).color),child:child?rgb(getComputedStyle(child).color):null};
      };
      if(mode==='warning_progress'){
        transition.currentTime=150;controller.renderStatus();
        programs.push({mode,states:[at(150)]});
      }else if(mode==='same_target'){
        transition.currentTime=150;controller.renderStatus();getComputedStyle(status).color;
        controller.showBufferWarning();
        const same=status.getAnimations().find(animation=>animation.transitionProperty==='color');
        if(same!==transition)throw new Error('Repeated warning restarted the source color transition');
        programs.push({mode,states:[at(150),at(225),at(300)]});
      }else if(mode==='reverse'||mode==='double_reverse'){
        transition.currentTime=150;getComputedStyle(status).color;
        callbacks[0]();
        await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);
        transition=status.getAnimations().find(animation=>animation.transitionProperty==='color');
        if(!transition)throw new Error('Missing reversed status transition');
        transition.pause();
        const reverseDuration=transition.effect.getTiming().duration;
        if(mode==='double_reverse'){
          transition.currentTime=50;getComputedStyle(status).color;
          controller.showBufferWarning();
          await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);
          transition=status.getAnimations().find(animation=>animation.transitionProperty==='color');
          if(!transition)throw new Error('Missing repeated reversed status transition');
          transition.pause();
          const repeatedDuration=transition.effect.getTiming().duration;
          programs.push({mode,reverseDuration,repeatedDuration,
            states:[at(0),at(repeatedDuration/2),at(repeatedDuration)]});
        }else programs.push({mode,reverseDuration,states:[at(0),at(reverseDuration/2),at(reverseDuration)]});
      }else programs.push({mode,states:[at(0),at(75),at(150),at(225),at(300)]});
    }
    return {rules,programs};
  },{css,methods});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original campaign input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_status_color_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules:captured.rules};
await writeFixtureJson(join(root,'data/campaign_status_color.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_status_color.json'),{...base,browser:browser.version(),programs:captured.programs});
console.log('CAMPAIGN_STATUS_COLOR_CAPTURE_PASS programs='+captured.programs.length);
