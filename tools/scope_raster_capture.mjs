import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/css/style.css','public/js/main.js','public/js/data.js','public/js/botPolicy.js',
  'public/js/balancePrefs.js','public/js/rng.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const d=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const main=(await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n');
const selectors=['.scope-vig','body.aiming .scope-vig','.env-fog','.weather-fog'];
const styles=selectors.map(selector=>{
  const at=css.indexOf(selector+' {'),end=css.indexOf('}',at);
  if(at<0||end<at)throw new Error('Missing original scope style: '+selector);
  return css.slice(at,end+1);
}).join('\n');
const callbacks={push:grabBlock(main,'const _pushScopeR = () =>'),fire:grabBlock(main,'envFog: (v) =>'),
  weather:grabBlock(main,'weatherFog: (d) =>')};
const formulas=Object.fromEntries(['scopeRvmin','fogSightMultByDensity','scopeRvminFog','weatherFogStops'].map(name=>[name,d[name].toString()]));
const constants={SCOPE:d.SCOPE,FOG_SIGHT:d.FOG_SIGHT,WEATHER_FOG_MASK:d.WEATHER_FOG_MASK};
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage({deviceScaleFactor:1}),cases=[];
  for(const viewport of [{width:640,height:360},{width:360,height:640},{width:128,height:128}]) {
    await page.setViewportSize(viewport);
    for(const [scoped,fire,weather]of [[false,0,0],[true,0,0],[false,0,.7],[false,.8,0],[true,.35,.7],[true,1,1]]) {
      const background=await page.evaluate(({styles,callbacks,formulas,constants,viewport,scoped,fire,weather})=>{
        document.head.replaceChildren();document.body.replaceChildren();document.body.className=scoped?'aiming':'';
        const style=document.createElement('style');style.textContent=styles+'\nhtml,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent;}';
        document.head.append(style);
        const canvas=document.createElement('canvas');canvas.width=viewport.width;canvas.height=viewport.height;
        canvas.style.cssText='position:absolute;inset:0;z-index:0';document.body.append(canvas);
        const context=canvas.getContext('2d');
        for(let y=0;y<canvas.height;y+=16)for(let x=0;x<canvas.width;x+=16) {
          context.fillStyle=((x/16+y/16)%2)?'#264258':'#d9c49e';context.fillRect(x,y,16,16);
        }
        for(const [id,name]of [['scopeVig','scope-vig'],['envFog','env-fog'],['weatherFog','weather-fog']]) {
          const element=document.createElement('div');element.id=id;element.className=name;document.body.append(element);
        }
        const factory=`${Object.entries(formulas).map(([name,text])=>'const '+name+' = '+text+';').join('\n')}
          let _scopeFireF=0,_scopeFogD=0;const _pushScopeR=()=>${callbacks.push};
          return {fire:(v)=>${callbacks.fire},weather:(d)=>${callbacks.weather}};`;
        const hud=new Function('$',...Object.keys(constants),factory)(id=>document.getElementById(id),...Object.values(constants));
        hud.fire(fire);hud.weather(weather);
        for(const id of ['envFog','weatherFog']) {
          const element=document.getElementById(id);getComputedStyle(element).opacity;
          for(const animation of element.getAnimations()){animation.pause();animation.currentTime=100000;}
        }
        return canvas.toDataURL('image/png').split(',')[1];
      },{styles,callbacks,formulas,constants,viewport,scoped,fire,weather});
      cases.push({viewport,scoped,fire,weather,background,png:(await page.screenshot({omitBackground:true})).toString('base64')});
    }
  }
  for(const [file,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during scope raster capture: '+file);
  const file='tools/scope_raster_capture.mjs';
  const inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/scope_raster.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),cases});
  console.log('SCOPE_RASTER_REFERENCES_PASS cases='+cases.length);
} finally {await browser.close();}
