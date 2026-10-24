import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/js/dialogue.js','public/css/style.css']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {Dialogue}=await import(pathToFileURL(join(source,'public/js/dialogue.js')).href);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const layers=[{rect:[2,2,68,48],color:'#db4932'},{rect:[24,12,66,45],color:'#365cd4'},{rect:[40,8,20,30],color:'#49b96a'}];
const programs=[],rules={};
try {
  for(const phase of ['enter','exit']) {
    const page=await browser.newPage({viewport:{width:96,height:80},deviceScaleFactor:1});
    const rule=await page.evaluate(({css,phase,method,layers})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css+'\nbody::before { display:none !important; }';
      document.body.style.cssText='margin:0;background:#192b3c';
      const el=document.createElement('div');el.className='dlg-bar';
      el.style.cssText='left:48px;bottom:16px;width:96px;height:64px;padding:0;border:0;border-radius:0;background:none;box-shadow:none';
      for(const layer of layers){const child=document.createElement('div');child.style.cssText=`position:absolute;left:${layer.rect[0]}px;top:${layer.rect[1]}px;width:${layer.rect[2]}px;height:${layer.rect[3]}px;background:${layer.color}`;el.appendChild(child);}
      document.body.appendChild(el);
      const removals=[];const context={bar:el,_after:(delay,callback)=>removals.push({delay,callback})};
      if(phase==='exit')new Function(`return ({${method}})._fadeOut`)().call(context,el);
      const animation=el.getAnimations()[0];
      if(!animation)throw new Error('Missing original radio animation');
      animation.pause();animation.currentTime=0;
      const timing=animation.effect.getTiming();
      const frames=animation.effect.getKeyframes();
      const curves={'ease-out':[0,0,.58,1],'ease-in':[.42,0,1,1]};
      if(!curves[frames[0].easing]||timing.fill!=='both'||timing.easing!=='linear')throw new Error('Unsupported original radio animation: '+JSON.stringify({timing,frames}));
      window.probe={el,animation,removals,context};
      return {duration:timing.duration/1000,curve:curves[frames[0].easing],from:Number(frames[0].opacity),to:Number(frames.at(-1).opacity),
        removal:removals[0]?.delay/1000??null};
    },{css,phase,method:Dialogue.prototype._fadeOut.toString(),layers});
    const frames=[];
    for(const time of [0,.016,.08,.16,.2,.319,.32,.399,.4,.419,.42]) {
      const state=await page.evaluate(time=>{
        const {el,animation}=window.probe;animation.currentTime=time*1000;
        const style=el.computedStyleMap(),transform=style.get('transform');
        if(transform.length!==1||transform[0].constructor.name!=='CSSTranslate')throw new Error('Unsupported original radio transform');
        return {opacity:style.get('opacity').value,y:transform[0].y.to('px').value};
      },time);
      frames.push({time,...state,png:(await page.screenshot({type:'png'})).toString('base64')});
    }
    rule.fromY=frames[0].y;rule.toY=frames.at(-1).y;
    if(phase==='exit'){
      const removed=await page.evaluate(()=>{const {removals,el,context}=window.probe;removals[0].callback();return !el.isConnected&&context.bar===null;});
      if(!removed)throw new Error('Original removal did not retire its exact bar');
    }
    rules[phase]=rule;programs.push({phase,frames});await page.close();
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during radio motion capture: '+file);
const file='tools/dialogue_motion_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'data/dialogue_motion.json'),{formatVersion:1,source:{inputs,sourceInputs},rules});
await writeFixtureJson(join(root,'tests/fixtures/dialogue_motion.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),rules,layers,programs});
console.log('DIALOGUE_MOTION_REFERENCES_PASS programs='+programs.length);
