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
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const {CHAPTER_SCENES}=await import(pathToFileURL(join(source,'public/js/chapterScenes.js')).href);
const scenes=[...PROLOGUE_SCENES,...Object.values(CHAPTER_SCENES).flatMap(value=>Object.values(value).flat())];
const functions=['easeInOutQuad','isLandscape','calcCameraTransform'].map(name=>grabFn(text,name)).join('\n');
const method=PrologueIntroController.prototype.setScene.toString();
const commands=[[0,[0,.01,.05,.25]],[1,[0,.04]],[0,[0,.02]],[1,[0,.05]],[.25,[0,.1]],[.5,[0,.25]],[.5,[.1,.25]],[0,[0,.249999,.25]]];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules;
try {
  const page=await browser.newPage();
  for(const landscape of [true,false]) {
    await page.setViewportSize(landscape?{width:1000,height:500}:{width:500,height:1000});
    const captured=await page.evaluate(({css,functions,method,scenes,commands,landscape})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      const calculate=new Function(`${functions}\nreturn calcCameraTransform;`)();
      const prototype=new Function(`return {${method}};`)(),programs=[];let rules;
      for(const scene of scenes) {
        document.body.innerHTML='<div class="prologue-scene-item" id="prologueSceneItem-0"><div class="prologue-fg-art"></div></div>';
        const element=document.querySelector('.prologue-fg-art');
        element.style.cssText='inset:auto;width:580px;height:580px';
        const context=Object.assign(Object.create(prototype),{root:document.body,scenes:[scene],activeSceneIdx:-1,
          content:null,dateTagEl:null,badgeEl:null,titleEl:null});
        const style=getComputedStyle(element),match=style.transitionTimingFunction.match(/^cubic-bezier\(([^)]+)\)$/);
        if(!match)throw new Error('Unsupported original camera transform transition');
        rules={duration:parseFloat(style.transitionDuration),curve:match[1].split(',').map(Number)};
        let animation=null,commandIndex=0,layout=[1000,500];const elapsed=new WeakMap(),frames=[];
        for(const [progress,samples]of commands) {
          const transform=calculate(scene.camera,progress),target=transform.match(/translate3d\(([-\d.]+)%, ([-\d.]+)%, 0\) scale\(([\d.]+)\)/);
          if(!target)throw new Error('Unsupported original camera target');
          context.setScene(0,transform);getComputedStyle(element).transform;
          animation=element.getAnimations()[0];if(animation)animation.pause();
          let last=0;
          for(let index=0;index<samples.length;index++) {
            const time=samples[index],delta=time-last;last=time;
            if(commandIndex===3&&index===1){layout=[1200,600];element.style.width='696px';element.style.height='696px';}
            if(animation){const value=(elapsed.get(animation)??0)+delta*1000;animation.currentTime=value;elapsed.set(animation,value);}
            const typed=element.computedStyleMap().get('transform');
            if(typed.length!==2||typed[0].constructor.name!=='CSSTranslate'||typed[1].constructor.name!=='CSSScale')
              throw new Error('Original transform requires unrounded typed CSS translate/scale values: '+String(typed));
            const percent=value=>[...value.toSum('px','percent').values].reduce((sum,term)=>{
              if(term.unit==='percent')return sum+term.value;
              if(term.unit==='px')return sum+term.value/parseFloat(getComputedStyle(element).width)*100;
              throw new Error('Unsupported original transform unit: '+term.unit);
            },0);
            const settled=!animation||Number(animation.currentTime)>=animation.effect.getComputedTiming().endTime;
            frames.push({progress,select:index===0,delta,time,settled,layout:[...layout],imageSize:parseFloat(getComputedStyle(element).width),target:{x:Number(target[1]),y:Number(target[2]),scale:Number(target[3])},
              pose:{x:percent(typed[0].x),y:percent(typed[0].y),scale:typed[1].x.value}});
          }
          commandIndex++;
        }
        programs.push({id:scene.id,camera:scene.camera,landscape,frames});
      }
      return {rules,programs};
    },{css,functions,method,scenes,commands,landscape});
    rules=captured.rules;programs.push(...captured.programs);
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during cinematic pose capture: '+file);
const file='tools/campaign_pose_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'data/campaign_pose.json'),{formatVersion:1,source:{inputs,sourceInputs},rules});
await writeFixtureJson(join(root,'tests/fixtures/campaign_pose.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),rules,programs});
console.log('CAMPAIGN_POSE_REFERENCES_PASS programs='+programs.length+' frames='+programs.reduce((sum,item)=>sum+item.frames.length,0));
