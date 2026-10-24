import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson,writeSourceFile} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/index.html','public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const css=(await readFile(join(source,'public/css/style.css'),'utf8'))
  +'\nhtml,body{background:transparent!important}body::before{display:none!important}';
const html=await readFile(join(source,'public/index.html'),'utf8');
const holder=html.match(/<div class="prologue-hold-indicator"[\s\S]*?<\/div>/)?.[0];
if(!holder)throw new Error('Missing original hold indicator');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const start=PrologueIntroController.prototype.startLongPress.toString();
const limits=[...start.matchAll(/Math\.max\((\d+), Math\.min\(window\.inner(?:Width|Height) - (\d+),/g)];
if(limits.length!==2||limits.some(row=>row[1]!==row[2]||row[1]!==limits[0][1]))throw new Error('Unsupported original hold clamp');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const browserVersion=browser.version();
let rules,programs,plate;const rasters=[];
try {
  const page=await browser.newPage({viewport:{width:400,height:400},deviceScaleFactor:1});
  const capture=await page.evaluate(({css,holder})=>{
    document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
    document.body.innerHTML=holder;document.body.style.background='transparent';
    const element=document.querySelector('.prologue-hold-indicator'),svg=element.querySelector('svg');
    const background=element.querySelector('.hold-bg'),progress=element.querySelector('.hold-progress');
    const computed=getComputedStyle(element),stroke=getComputedStyle(progress),label=element.querySelector('.hold-text');
    const rgba=value=>{const match=value.match(/[\d.]+/g).map(Number);return [match[0]/255,match[1]/255,match[2]/255,match[3]??1];};
    const rules={size:[parseFloat(computed.width),parseFloat(computed.height)],radius:Number(progress.getAttribute('r')),pathLength:progress.getTotalLength(),
      strokeWidth:parseFloat(stroke.strokeWidth),color:rgba(stroke.stroke),dashArray:parseFloat(stroke.strokeDasharray),
      initialOffset:parseFloat(stroke.strokeDashoffset),opacityDuration:parseFloat(computed.transitionDuration),
      opacityCurve:computed.transitionTimingFunction,dashDuration:parseFloat(stroke.transitionDuration),dashCurve:stroke.transitionTimingFunction};
    if(svg.getAttribute('viewBox')!=='0 0 60 60'||getComputedStyle(svg).width!=='60px'||getComputedStyle(svg).height!=='60px'
      ||getComputedStyle(svg).transform!=='matrix(0, -1, 1, 0, 0, 0)'||stroke.strokeLinecap!=='round'
      ||background.getAttribute('r')!==progress.getAttribute('r')||rules.opacityCurve!=='ease'||rules.dashCurve!=='linear')
      throw new Error('Unsupported original hold shape');
    const nativeSvg=svg.cloneNode(false),nativeCircle=progress.cloneNode(false),group=document.createElementNS('http://www.w3.org/2000/svg','g');
    nativeSvg.removeAttribute('class');nativeSvg.setAttribute('width','60');nativeSvg.setAttribute('height','60');
    nativeCircle.removeAttribute('class');nativeCircle.removeAttribute('id');
    for(const property of ['fill','stroke','stroke-width','stroke-linecap','stroke-dasharray'])
      nativeCircle.setAttribute(property,stroke.getPropertyValue(property));
    nativeCircle.setAttribute('stroke-dashoffset','OFFSET');
    group.setAttribute('transform','translate(30 30) matrix(0 -1 1 0 0 0) translate(-30 -30)');
    group.append(nativeCircle);nativeSvg.append(group);
    rules.progressSvg=new XMLSerializer().serializeToString(nativeSvg);
    element.style.cssText='left:200px;top:200px;opacity:1;transition:none';progress.style.visibility='hidden';
    const bounds=element.getBoundingClientRect(),text=label.getBoundingClientRect();
    const shadows=getComputedStyle(label).textShadow.match(/-?[\d.]+px/g).map(parseFloat);
    if(shadows.length!==3)throw new Error('Unsupported original hold text shadow');
    const pad=Math.ceil(Math.max(Math.abs(shadows[0]),Math.abs(shadows[1]))+shadows[2]*2);
    const left=Math.floor(Math.min(bounds.left,text.left)-pad),top=Math.floor(Math.min(bounds.top,text.top)-pad);
    const clip={x:left,y:top,width:Math.ceil(Math.max(bounds.right,text.right)+pad)-left,height:Math.ceil(Math.max(bounds.bottom,text.bottom)+pad)-top};
    return {rules,clip,imageOffset:[left-200,top-200]};
  },{css,holder});
  plate=await page.screenshot({omitBackground:true,clip:capture.clip});
  rules={...capture.rules,edge:Number(limits[0][1]),imageOffset:capture.imageOffset,
    imageSize:[capture.clip.width,capture.clip.height],image:'res://assets/ui/campaign_hold.res',plate:'res://assets/ui/campaign_hold.png'};
  programs=await page.evaluate(({css,holder,rules})=>{
    document.head.firstChild.textContent=css;
    const programs=[];
    for(const channel of ['opacity','stroke-dashoffset'])for(const commands of [
      [[1,[0,.01,.04,.1,.2]],[0,[0,.01,.04,.1,.2]]],
      [[1,[0,.01,.04]],[0,[0,.01]],[1,[0,.01,.04,.2]]],
      [[.4,[0,.01,.02]],[.6,[0,.01,.02]],[.8,[0,.01,.02,.2]]],
      [[1,[0]],[0,[0,.01,.2]],[1,[0,.01,.2]]],
      [[1,[0,.04]],[1,[.08,.1,.2]]],
    ]) {
      document.body.innerHTML=holder;
      const element=document.querySelector(channel==='opacity'?'.prologue-hold-indicator':'.hold-progress');
      const base=channel==='opacity'?0:rules.initialOffset,unit=channel==='opacity'?1:rules.initialOffset;
      getComputedStyle(element).getPropertyValue(channel);
      let previous=null;const frames=[];
      for(const [value,samples]of commands) {
        const target=channel==='opacity'?value:base-unit*value;
        element.style.setProperty(channel,String(target));getComputedStyle(element).getPropertyValue(channel);
        const animation=element.getAnimations()[0];if(animation)animation.pause();
        for(const time of samples) {
          if(animation)animation.currentTime=time*1000;
          frames.push({target,time,newTransition:animation!==previous,
            value:parseFloat(getComputedStyle(element).getPropertyValue(channel))});previous=animation;
        }
      }
      programs.push({channel,frames});
    }
    return programs;
  },{css,holder,rules});
  await page.setViewportSize({width:128,height:128});
  for(const [opacity,progress,stroke]of [[1,0,false],[.35,0,false],[1,0,true],[1,.25,true],[1,.5,true],[1,1,true],[.35,.5,true]]) {
    const offset=Math.PI*2*rules.radius*(1-progress);
    await page.evaluate(({holder,opacity,offset,stroke})=>{
      document.body.innerHTML=holder;
      const element=document.querySelector('.prologue-hold-indicator'),circle=element.querySelector('.hold-progress');
      element.style.cssText=`left:64px;top:48px;opacity:${opacity};transition:none`;
      circle.style.cssText=`stroke-dashoffset:${offset};transition:none;visibility:${stroke?'visible':'hidden'}`;
    },{holder,opacity,offset,stroke});
    rasters.push({opacity,offset,stroke,png:(await page.screenshot({omitBackground:true})).toString('base64')});
  }
} finally {await browser.close();}
const saved=Object.fromEntries(['window','performance','requestAnimationFrame','cancelAnimationFrame'].map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]));
const motion=[];
try {
  for(const viewport of [[1024,768],[360,640],[80,80]])for(const point of [[0,0],[-20,900],[2000,-20],[120.25,220.75]]) {
    let now=1000,serial=0;const rafs=new Map(),classes=new Set();
    for(const [key,value]of Object.entries({window:{innerWidth:viewport[0],innerHeight:viewport[1]},performance:{now:()=>now},
      requestAnimationFrame:callback=>{const id=++serial;rafs.set(id,callback);return id;},cancelAnimationFrame:id=>rafs.delete(id)}))
      Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
    const context=Object.assign(Object.create(PrologueIntroController.prototype),{destroyed:false,holdRaf:null,
      holdIndicator:{style:{},classList:{add:key=>classes.add(key),remove:key=>classes.delete(key)}},holdCircle:{style:{}}});
    const frames=[];
    for(const operation of [{type:'begin',time:1000},{type:'frame',time:1010},{type:'begin',time:1100},{type:'frame',time:1200},
      {type:'cancel',time:1250},{type:'begin',time:1400},{type:'frame',time:1500},{type:'cancel',time:1501}]) {
      now=operation.time;
      if(operation.type==='begin')context.startLongPress({clientX:point[0],clientY:point[1]});
      if(operation.type==='cancel')context.cancelLongPress();
      if(operation.type==='frame'){const pending=[...rafs];rafs.clear();for(const [,callback]of pending)callback();}
      frames.push({operation,active:classes.has('active'),position:[parseFloat(context.holdIndicator.style.left),parseFloat(context.holdIndicator.style.top)],offset:Number(context.holdCircle.style.strokeDashoffset)});
    }
    motion.push({viewport,point,frames});
  }
} finally {
  for(const [key,descriptor]of Object.entries(saved)){if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];}
}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during hold capture: '+file);
const file='tools/campaign_hold_capture.mjs';
const inputs={};
for(const input of [file,'tools/import_campaign_hold.gd'])
  inputs[input]=digest((await readFile(join(root,input),'utf8')).replace(/\r\n?/g,'\n'));
await mkdir(join(root,'assets/ui'),{recursive:true});
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeSourceFile(join(root,'assets/ui/campaign_hold.png'),plate);
await writeFixtureJson(join(root,'data/campaign_hold.json'),{formatVersion:1,source:{inputs,sourceInputs},rules,plateSha256:digest(plate)});
await writeFixtureJson(join(root,'tests/fixtures/campaign_hold.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browserVersion,rules,programs,motion,rasters,plateSha256:digest(plate)});
console.log('CAMPAIGN_HOLD_REFERENCES_PASS transitions='+programs.length+' motion='+motion.length);
