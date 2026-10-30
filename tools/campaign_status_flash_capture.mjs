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
const methods=['renderStatus','showBufferWarning'].map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let captured;
try{
  const page=await browser.newPage({viewport:{width:640,height:360},deviceScaleFactor:1});
  captured=await page.evaluate(async ({css,html,methods})=>{
    document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
    const keyframes=[...document.head.firstChild.sheet.cssRules].find(rule=>rule.name==='flashWarn');
    if(!keyframes)throw new Error('Original flash keyframes missing');
    const middle=[...keyframes.cssRules].find(rule=>rule.keyText==='50%');
    const outer=[...keyframes.cssRules].find(rule=>rule.keyText==='0%, 100%');
    if(!middle||!outer)throw new Error('Original flash keyframe positions changed');
    const scale=rule=>{
      const match=rule.style.transform.match(/^scale\(([\d.]+)\)$/);
      if(!match)throw new Error('Unsupported original flash transform');
      return Number(match[1]);
    };
    const programs=[];let rules;
    for(const mode of ['flash','repeat','progress','expire','reopen','completed_repeat']){
      document.body.innerHTML='';
      const root=new DOMParser().parseFromString(html,'text/html').querySelector('#prologueIntro');
      root.style.display='flex';document.body.append(root);
      const status=root.querySelector('#prologueBufferStatus'),hint=root.querySelector('#prologueSkipHint');
      const callbacks=[];
      const Controller=new Function('setTimeout','return class {'+methods.join('\n')+'}')(
        callback=>{callbacks.push(callback);return callbacks.length;});
      const controller=Object.assign(new Controller(),{statusEl:status,skipHintEl:hint,isBufferComplete:false,
        bufferPercent:58,destroyed:false});
      controller.renderStatus();getComputedStyle(status).color;controller.showBufferWarning();
      await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);
      let animation=status.getAnimations().find(item=>item.animationName==='flashWarn');
      if(!animation)throw new Error('Original status flash animation missing');
      animation.pause();
      const computed=getComputedStyle(status);
      const current={duration:parseFloat(computed.animationDuration),iterations:Number(computed.animationIterationCount),
        curve:computed.animationTimingFunction,normalOpacity:Number(outer.style.opacity),peakOpacity:Number(middle.style.opacity),
        normalScale:scale(outer),peakScale:scale(middle)};
      if(current.curve!=='ease')throw new Error('Unsupported original flash easing: '+current.curve);
      current.curve=[.25,.1,.25,1];
      if(rules&&JSON.stringify(rules)!==JSON.stringify(current))throw new Error('Original flash rules vary');
      rules=current;
      const at=ms=>{
        if(animation)animation.currentTime=ms;
        const map=status.computedStyleMap(),transform=map.get('transform');
        const scaleValue=transform.toString()==='none'?1:transform.toMatrix().a;
        return {ms,opacity:map.get('opacity').value,scale:scaleValue};
      };
      if(mode==='flash'){
        programs.push({mode,states:[0,43.75,87.5,131.25,175,218.75,262.5,350,437.5,525,700].map(at)});
      }else if(mode==='completed_repeat'){
        at(701);controller.showBufferWarning();
        const retained=status.getAnimations().find(item=>item.animationName==='flashWarn');
        if(retained&&retained!==animation)throw new Error('A completed flash unexpectedly restarted');
        programs.push({mode,states:[at(701),at(900)]});
      }else if(mode==='repeat'||mode==='progress'){
        at(200);
        if(mode==='repeat')controller.showBufferWarning();else controller.renderStatus();
        const retained=status.getAnimations().find(item=>item.animationName==='flashWarn');
        if(retained!==animation)throw new Error('Original flash unexpectedly restarted: '+mode);
        programs.push({mode,states:[at(200),at(350),at(525),at(700)]});
      }else if(mode==='expire'){
        at(200);callbacks[0]();getComputedStyle(status).opacity;
        animation=null;
        programs.push({mode,warning:status.classList.contains('flash-warn'),states:[at(0)]});
      }else{
        at(200);root.style.display='none';getComputedStyle(status).opacity;
        root.style.display='flex';
        await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);
        const reopened=status.getAnimations().find(item=>item.animationName==='flashWarn');
        if(!reopened||reopened===animation)throw new Error('Original flash did not restart after hiding');
        animation=reopened;animation.pause();
        programs.push({mode,warning:status.classList.contains('flash-warn'),states:[at(0),at(175),at(350)]});
      }
    }
    return {rules,programs};
  },{css,html,methods});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original campaign input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_status_flash_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules:captured.rules};
await writeFixtureJson(join(root,'data/campaign_status_flash.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_status_flash.json'),{...base,browser:browser.version(),programs:captured.programs});
console.log('CAMPAIGN_STATUS_FLASH_CAPTURE_PASS programs='+captured.programs.length);
