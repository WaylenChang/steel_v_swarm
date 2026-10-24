import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve,extname,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/js/dialogue.js','public/js/storytalk.js','public/js/portraits.js','public/js/data.js','public/js/lore.js',
  'public/js/botPolicy.js','public/js/balancePrefs.js','public/js/rng.js','public/css/style.css']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {STORY_TALK}=await import(pathToFileURL(join(source,'public/js/storytalk.js')).href);
const scenes=Object.values(STORY_TALK).flatMap(chapter=>Object.values(chapter).flatMap(side=>Object.values(side)));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
let motion,scrollPrograms,nestedScrollPrograms;
const layers=[{rect:[2,2,68,48],color:'#db4932'},{rect:[24,12,66,45],color:'#365cd4'},{rect:[40,8,20,30],color:'#49b96a'}];
try {
  const page=await browser.newPage({viewport:{width:400,height:300},deviceScaleFactor:1});
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.origin!=='http://source.invalid')return route.abort();
    if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><head></head><body></body></html>'});
    const base=resolve(source,'public'),path=resolve(base,decodeURIComponent(url.pathname).slice(1));
    if(!path.startsWith(base+sep))throw new Error('Source route escapes public directory');
    try {await route.fulfill({contentType:extname(path)==='.js'?'text/javascript':extname(path)==='.css'?'text/css':'application/octet-stream',body:await readFile(path)});}
    catch {await route.fulfill({status:404,body:''});}
  });
  await page.goto('http://source.invalid/');
  await page.evaluate(async()=>{window.Dialogue=(await import('/js/dialogue.js')).Dialogue;});
  for(const scene of scenes)for(const side of ['STEEL','SWARM',''])for(const artMode of ['char','mech']) {
    const program=await page.evaluate(({scene,side,artMode,css})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div id="host"></div>';
      const host=document.getElementById('host'),dialogue=new window.Dialogue(host,{mySide:side,artMode});
      const saved={setTimeout:window.setTimeout,clearTimeout:window.clearTimeout};
      let now=0,serial=0;const tasks=new Map();
      window.setTimeout=(callback,delay)=>{const id=++serial;tasks.set(id,{callback,at:now+delay});return id;};
      window.clearTimeout=id=>tasks.delete(id);
      try {
        const wrap=dialogue.scene(host,scene),rows=[...wrap.querySelectorAll('.dlg-say')];
        const snapshot=()=>({visible:rows.map(row=>row.classList.contains('on')),timers:[...tasks.values()].map(task=>(task.at-now)/1000).sort((a,b)=>a-b)});
        const frames=[{action:'start',time:0,state:snapshot()}];
        const metadata=rows.map(row=>({text:row.querySelector('.dlg-line').textContent,speaker:row.querySelector('.dlg-who').textContent,
          flip:row.classList.contains('flip'),portrait:row.querySelector('img').getAttribute('src')}));
        while(tasks.size){const [id,task]=[...tasks].sort((a,b)=>a[1].at-b[1].at)[0];tasks.delete(id);now=task.at;task.callback();frames.push({action:'timer',time:now/1000,state:snapshot()});}
        dialogue.scene(host,scene);dialogue.clear();
        frames.push({action:'clear',time:now/1000,state:snapshot()});
        return {scene,side,artMode,metadata,frames};
      } finally {Object.assign(window,saved);}
    },{scene,side,artMode,css});
    programs.push(program);
  }
  motion=await page.evaluate(css=>{
    document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
    document.body.innerHTML='<div class="dlg-say" id="row"></div>';
    const row=document.getElementById('row');
    const before=row.computedStyleMap(),from=before.get('opacity').value,fromY=before.get('transform')[0].y.to('px').value;
    row.classList.add('on');getComputedStyle(row).opacity;
    const animations=row.getAnimations();
    if(animations.length!==2)throw new Error('Expected original opacity/translation transitions');
    for(const animation of animations)animation.pause();
    const timing=animations[0].effect.getTiming();
    if(animations.some(animation=>animation.effect.getTiming().duration!==timing.duration)||!['ease-out','cubic-bezier(0, 0, 0.58, 1)'].includes(timing.easing))throw new Error('Unsupported transcript easing: '+JSON.stringify(animations.map(animation=>({timing:animation.effect.getTiming(),frames:animation.effect.getKeyframes()}))));
    const frames=[];
    for(const time of [0,.016,.05,.1,.13,.2,.259,.26,.3]){
      for(const animation of animations)animation.currentTime=time*1000;
      const style=row.computedStyleMap(),transform=style.get('transform');
      frames.push({time,opacity:style.get('opacity').value,y:transform.toString()==='none'?0:transform[0].y.to('px').value});
    }
    return {duration:timing.duration/1000,curve:[0,0,.58,1],from,fromY,to:frames.at(-1).opacity,toY:frames.at(-1).y,frames};
  },css);
  await page.setViewportSize({width:96,height:80});
  await page.evaluate(({css,layers})=>{
    document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css+'\nbody::before {display:none !important;}';
    document.body.style.cssText='margin:0;background:#192b3c';
    document.body.innerHTML='<div class="dlg-say" id="row" style="position:absolute;left:0;top:0;width:96px;height:64px;display:block"></div>';
    const row=document.getElementById('row');
    for(const layer of layers){const child=document.createElement('div');child.style.cssText=`position:absolute;left:${layer.rect[0]}px;top:${layer.rect[1]}px;width:${layer.rect[2]}px;height:${layer.rect[3]}px;background:${layer.color}`;row.appendChild(child);}
    getComputedStyle(row).opacity;row.classList.add('on');getComputedStyle(row).opacity;
    window.motionAnimations=row.getAnimations();for(const animation of window.motionAnimations)animation.pause();
  },{css,layers});
  for(const frame of motion.frames){
    await page.evaluate(time=>{for(const animation of window.motionAnimations)animation.currentTime=time*1000;},frame.time);
    frame.png=(await page.screenshot({type:'png'})).toString('base64');
  }
  await page.setViewportSize({width:400,height:300});
  scrollPrograms=await page.evaluate(()=>{
    document.head.innerHTML='';document.body.style.cssText='margin:0;overflow:hidden';
    const programs=[];
    for(const height of [40,100,160])for(const top of [0,20,20.5,80,120,200])for(const initial of [0,30,90,200]){
      document.body.innerHTML='<div id="viewport" style="width:200px;height:100px;overflow:auto"><div style="position:relative;height:500px"><div id="target"></div></div></div>';
      const viewport=document.getElementById('viewport'),target=document.getElementById('target');
      target.style.cssText=`position:absolute;left:0;top:${top}px;width:100px;height:${height}px;transform:translateY(6px)`;
      viewport.scrollTop=initial;target.scrollIntoView({block:'nearest'});
      programs.push({height,top,initial,scroll:viewport.scrollTop});
    }
    return programs;
  });
  nestedScrollPrograms=await page.evaluate(()=>{
    const programs=[];
    for(const height of [40,160])for(const top of [0,80,200])for(const innerStart of [0,90])for(const outerStart of [0,180,280]){
      document.body.innerHTML='<div id="outer" style="width:240px;height:120px;overflow:auto"><div style="position:relative;height:900px"><div id="inner" style="position:absolute;top:200px;left:0;width:200px;height:100px;overflow:auto"><div style="position:relative;height:500px"><div id="target"></div></div></div></div></div>';
      const outer=document.getElementById('outer'),inner=document.getElementById('inner'),target=document.getElementById('target');
      target.style.cssText=`position:absolute;left:0;top:${top}px;width:100px;height:${height}px;transform:translateY(6px)`;
      outer.scrollTop=outerStart;inner.scrollTop=innerStart;target.scrollIntoView({block:'nearest'});
      programs.push({height,top,innerStart,outerStart,inner:inner.scrollTop,outer:outer.scrollTop});
    }
    return programs;
  });
  await page.close();
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during transcript capture: '+file);
const file='tools/dialogue_transcript_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
const sourceIdentity={inputs,sourceInputs};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'data/dialogue_transcript.json'),{formatVersion:1,source:sourceIdentity,motion});
await writeFixtureJson(join(root,'tests/fixtures/dialogue_transcript.json'),{formatVersion:1,source:sourceIdentity,browser:browser.version(),motion,layers,programs,scrollPrograms,nestedScrollPrograms});
console.log('DIALOGUE_TRANSCRIPT_REFERENCES_PASS programs='+programs.length);
