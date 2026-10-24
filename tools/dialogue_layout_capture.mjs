import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve,extname,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/index.html','public/js/main.js','public/js/dialogue.js','public/js/storytalk.js','public/js/portraits.js',
  'public/js/data.js','public/js/lore.js','public/js/botPolicy.js','public/js/balancePrefs.js','public/js/rng.js','public/css/style.css']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const html=await readFile(join(source,'public/index.html'),'utf8'),css=await readFile(join(source,'public/css/style.css'),'utf8');
const {STORY_TALK}=await import(pathToFileURL(join(source,'public/js/storytalk.js')).href);
const scenes=Object.entries(STORY_TALK).flatMap(([chapter,sides])=>Object.entries(sides).map(([side,stages])=>({chapter,side,scene:stages.base})));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const output=join(root,'build/dialogue_layout');await mkdir(join(output,'fonts'),{recursive:true});
const programs=[],fontResponses=new Map(),assetInputs={},pending=[];
try {
  const page=await browser.newPage({deviceScaleFactor:1});
  page.on('response',response=>{
    const url=new URL(response.url());
    if(!['fonts.googleapis.com','fonts.gstatic.com'].includes(url.hostname)||!response.ok())return;
    pending.push((async()=>{const bytes=await response.body(),hash=digest(bytes),extension=url.hostname==='fonts.googleapis.com'?'.css':extname(url.pathname);
      const path='fonts/'+hash+extension;await writeFile(join(output,path),bytes);
      fontResponses.set(response.url(),{url:response.url(),sha256:hash,bytes:bytes.length,path});})());
  });
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(['fonts.googleapis.com','fonts.gstatic.com'].includes(url.hostname))return route.continue();
    if(url.origin!=='http://source.invalid')return route.abort();
    if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><head></head><body></body></html>'});
    const base=resolve(source,'public'),path=resolve(base,decodeURIComponent(url.pathname).slice(1));
    if(!path.startsWith(base+sep))throw new Error('Source route escapes public directory');
    try {const bytes=await readFile(path);if(url.pathname.startsWith('/assets/'))assetInputs['public'+decodeURIComponent(url.pathname)]=digest(bytes);
      await route.fulfill({contentType:extname(path)==='.js'?'text/javascript':extname(path)==='.css'?'text/css':extname(path)==='.png'?'image/png':'application/octet-stream',body:bytes});}
    catch {await route.fulfill({status:404,body:''});}
  });
  await page.goto('http://source.invalid/');
  await page.evaluate(async({html,css})=>{
    const original=new DOMParser().parseFromString(html,'text/html');
    const loading=[];
    for(const link of original.querySelectorAll('link[rel="stylesheet"]'))if(new URL(link.href).hostname==='fonts.googleapis.com'){
      const copy=document.importNode(link,true);loading.push(new Promise((resolve,reject)=>{copy.onload=resolve;copy.onerror=()=>reject(new Error('Original web font stylesheet failed'));}));document.head.appendChild(copy);
    }
    if(loading.length!==1)throw new Error('Expected the original web font stylesheet');
    const style=document.createElement('style');style.textContent=css+'\nbody::before {display:none !important;}';document.head.appendChild(style);
    document.body.style.background='#192b3c';window.overlayHTML=original.getElementById('overOverlay').outerHTML;
    window.Dialogue=(await import('/js/dialogue.js')).Dialogue;await Promise.all(loading);
  },{html,css});
  const cdp=await page.context().newCDPSession(page);await cdp.send('DOM.enable');await cdp.send('CSS.enable');
  for(const viewport of [{width:360,height:640},{width:720,height:900},{width:721,height:900},{width:1440,height:900}]) {
    await page.setViewportSize(viewport);
    for(const item of scenes)for(const artMode of ['char','mech']) {
      const state=await page.evaluate(async({item,artMode})=>{
        document.body.innerHTML=window.overlayHTML;document.getElementById('overOverlay').style.display='flex';
        const tasks=[],dialogue=new window.Dialogue(document.getElementById('overTalk'),{mySide:item.side,artMode});
        dialogue._after=(_delay,callback)=>tasks.push(callback);
        const wrap=dialogue.scene(document.getElementById('overTalk'),item.scene);
        await Promise.all([...wrap.querySelectorAll('img')].map(image=>image.decode().catch(()=>null)));await document.fonts.ready;
        getComputedStyle(wrap).height;for(const callback of tasks)callback();
        for(const animation of wrap.getAnimations({subtree:true}))animation.finish();await document.fonts.ready;
        const origin=wrap.getBoundingClientRect();
        const styles=['display','position','boxSizing','width','height','maxHeight','paddingTop','paddingRight','paddingBottom','paddingLeft',
          'gap','opacity','transform','maskImage','backgroundColor','borderRadius','borderWidth','borderStyle','borderColor','outline','outlineOffset',
          'clipPath','fontFamily','fontSize','fontWeight','lineHeight','letterSpacing','textAlign','alignItems','flexDirection','objectFit'];
        const measure=element=>{const rectangle=element.getBoundingClientRect(),style=getComputedStyle(element);return {
          rect:[rectangle.x-origin.x,rectangle.y-origin.y,rectangle.width,rectangle.height],style:Object.fromEntries(styles.map(key=>[key,style[key]]))};};
        const script=wrap.querySelector('.dlg-script');
        return {bounds:[origin.x,origin.y,origin.width,origin.height],wrap:measure(wrap),header:measure(wrap.querySelector('.dlg-scene-h')),body:measure(wrap.querySelector('.dlg-scene-body')),
          script:{...measure(script),scrollTop:script.scrollTop,scrollHeight:script.scrollHeight,clientHeight:script.clientHeight},
          portraits:[...wrap.querySelectorAll('.dlg-art')].map(image=>({...measure(image),src:image.getAttribute('src'),decoded:image.complete&&image.naturalWidth>0,natural:[image.naturalWidth,image.naturalHeight]})),
          rows:[...wrap.querySelectorAll('.dlg-say')].map(row=>({...measure(row),avatar:measure(row.querySelector('.dlg-av')),text:measure(row.querySelector('.dlg-txt')),
            speaker:{...measure(row.querySelector('.dlg-who')),value:row.querySelector('.dlg-who').textContent},line:{...measure(row.querySelector('.dlg-line')),value:row.querySelector('.dlg-line').textContent}}))};
      },{item,artMode});
      const document=await cdp.send('DOM.getDocument'),fonts={};
      for(const [name,selector]of [['header','.dlg-scene-h b'],['speaker','.dlg-who'],['line','.dlg-line']]){
        const {nodeId}=await cdp.send('DOM.querySelector',{nodeId:document.root.nodeId,selector});fonts[name]=(await cdp.send('CSS.getPlatformFontsForNode',{nodeId})).fonts;
      }
      if(!fonts.line.some(font=>font.isCustomFont&&font.familyName.startsWith('Noto Sans TC')))throw new Error('Original Noto Sans TC did not render the transcript: '+JSON.stringify(fonts));
      const name=`${viewport.width}x${viewport.height}_${item.chapter}_${item.side}_${artMode}.png`;
      const png=await page.locator('.dlg-scene').screenshot({path:join(output,name),animations:'disabled'});
      programs.push({viewport,chapter:item.chapter,side:item.side,artMode,scene:item.scene,state,fonts,image:{name,sha256:digest(png),png:png.toString('base64')}});
    }
    console.log('DIALOGUE_LAYOUT_VIEWPORT_CAPTURED '+viewport.width+'x'+viewport.height);
  }
  await Promise.all(pending);await cdp.detach();await page.close();
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during dialogue layout capture: '+file);
for(const [file,expected]of Object.entries(assetInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source asset changed during dialogue layout capture: '+file);
const file='tools/dialogue_layout_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/dialogue_layout.json'),{formatVersion:1,
  source:{inputs,sourceInputs,assetInputs:Object.fromEntries(Object.entries(assetInputs).sort(([a],[b])=>a.localeCompare(b)))},browser:browser.version(),
  host:{markup:'overOverlay',populatedFields:['overTalk'],bodyClasses:[],backdrop:'#192b3c'},
  fonts:[...fontResponses.values()].sort((a,b)=>a.url.localeCompare(b.url)),programs});
console.log('DIALOGUE_LAYOUT_REFERENCES_PASS programs='+programs.length+' fontResources='+fontResponses.size);
