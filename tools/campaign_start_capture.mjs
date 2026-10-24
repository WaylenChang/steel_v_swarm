import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),sourceInputs={};
for(const file of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const text=await readFile(join(source,'public/js/prologue.js'),'utf8');
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const functions=['easeInOutQuad','isLandscape','calcCameraTransform'].map(name=>grabFn(text,name)).join('\n');
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const scenes=PROLOGUE_SCENES.slice(0,3);
const geometries=[
  [{top:10,height:200},{top:234,height:160},{top:418,height:220}],
  [{top:0,height:0},{top:0,height:0},{top:0,height:0}],
  [{top:0,height:50},{top:74,height:80},{top:178,height:80}],
  [{top:0,height:50},{top:74,height:0},{top:98,height:220}],
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try {
  for(const landscape of [true,false])for(const sections of geometries)for(const start of [-3,0,1,2,99]) {
    const page=await browser.newPage({viewport:landscape?{width:1000,height:500}:{width:500,height:1000}});
    const result=await page.evaluate(({controller,functions,scenes,sections,start})=>{
      document.body.innerHTML='<div id="prologueIntro"><div id="prologueCrawlViewport" style="width:320px;height:100px;overflow:auto"><div style="height:260px"></div></div></div>';
      const callbacks=[];
      const Controller=new Function('performance','requestAnimationFrame','cancelAnimationFrame',`${functions}\nreturn (${controller});`)(
        {now:()=>1000},callback=>{callbacks.push(callback);return callbacks.length;},()=>{});
      const context=new Controller({isPrologue:false,scenes});
      const metrics=sections.map(value=>({offsetTop:value.top,offsetHeight:value.height,classList:{toggle(){}}}));
      context.content={querySelectorAll:()=>metrics,querySelector:selector=>metrics[Number(selector.match(/"(\d+)"/)[1])]};
      context.initDOM=()=>{};
      const targets=scenes.map(()=>({scale:1,x:0,y:0}));
      const original=context.setScene;
      context.setScene=function(index,transform){
        original.call(this,index,transform);
        if(transform){const match=transform.match(/translate3d\(([-\d.]+)%, ([-\d.]+)%, 0\) scale\(([\d.]+)\)/);
          if(!match)throw new Error('Unsupported source camera target');
          targets[index]={x:Number(match[1]),y:Number(match[2]),scale:Number(match[3])};}
      };
      const snapshot=()=>({active:context.activeSceneIdx,scroll:context.viewport.scrollTop,targets:targets.map(value=>({...value}))});
      context.play(start);
      const initial=snapshot();
      const clamped=Math.max(0,Math.min(scenes.length-1,start));
      if(clamped>0)callbacks.shift()(1000);
      return {initial,jump:snapshot(),geometry:{width:context.viewport.clientWidth,height:context.viewport.clientHeight,scrollHeight:context.viewport.scrollHeight,sections}};
    },{controller:PrologueIntroController.toString(),functions,scenes,sections,start});
    programs.push({landscape,start,...result});await page.close();
  }
} finally {await browser.close();}
for(const [file,expected]of Object.entries(sourceInputs))if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during cinematic start capture: '+file);
const file='tools/campaign_start_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
await mkdir(join(root,'tests/fixtures'),{recursive:true});
await writeFixtureJson(join(root,'tests/fixtures/campaign_start.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),scenes,programs});
console.log('CAMPAIGN_START_REFERENCES_PASS programs='+programs.length);
