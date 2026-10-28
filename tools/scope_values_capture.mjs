import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/scope_values_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/data.js','public/js/main.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabBlock,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const data=contents['public/js/data.js'],main=contents['public/js/main.js'];
const expression=name=>{
  const match=new RegExp('^export const '+name+' = [\\s\\S]*?;', 'm').exec(data);
  if(!match)throw new Error('Missing original expression: '+name);
  return match[0].replace(/^export /,'');
};
const stopPrefix='export const weatherFogStops = (d = 0) =>';
const definitions=[...['SCOPE','FOG_SIGHT','WEATHER_FOG_MASK'].map(name=>grabConst(data,name)),
  ...['scopeRvmin','fogSightMultByDensity','scopeRvminFog'].map(expression),
  'const weatherFogStops = (d = 0) => '+grabBlock(data,stopPrefix)+';'].join('\n');
const callbacks={push:grabBlock(main,'const _pushScopeR = () =>'),fire:grabBlock(main,'envFog: (v) =>'),
  weather:grabBlock(main,'weatherFog: (d) =>')};

const inputs=[];
for(let fire=0;fire<=10;fire++)for(let weather=0;weather<=10;weather++)
  for(const scoped of [false,true])inputs.push({fire:fire/10,weather:weather/10,scoped,group:'grid'});
for(let n=385;n<550;n+=5) {
  const weather=(0.55-(n+0.5)/1000)*6;
  for(const offset of [-1e-10,0,1e-10])for(const scoped of [false,true])
    inputs.push({fire:0.37,weather:weather+offset,scoped,group:'weather-boundary'});
}
for(let n=18;n<40;n++) {
  for(const weather of [0,0.05]) {
    const multiplier=1-(1-1/3)*weather;
    const fire=(40-(n+0.05)/multiplier)/22;
    if(fire<0||fire>1)continue;
    for(const offset of [-1e-14,0,1e-14])
      inputs.push({fire:fire+offset,weather,scoped:true,group:'radius-boundary'});
  }
}
for(let n=0;n<60;n++) {
  const fire=(n/10+0.005)/6;
  for(const offset of [-1e-15,0,1e-15])
    inputs.push({fire:fire+offset,weather:0.4,scoped:false,group:'blur-boundary'});
}
const commands=[
  [{fire:0.2,weather:0.8,scoped:false},{fire:0.9,weather:0,scoped:false},
    {fire:0.4,weather:0,scoped:true},{fire:0.1,weather:0.6,scoped:true}],
  [{fire:0.3,weather:0.7,scoped:true},{fire:0.8,weather:0,scoped:true},
    {fire:0.5,weather:0,scoped:false},{fire:0.1,weather:0.4,scoped:false}],
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage();
  const capture=await page.evaluate(({definitions,callbacks,inputs,commands})=>{
    const fire=document.createElement('div'),weather=document.createElement('div');
    fire.id='envFog';weather.id='weatherFog';document.body.append(fire,weather);
    const factory=definitions+'\nlet _scopeFireF=0,_scopeFogD=0;const _pushScopeR=()=>'+callbacks.push+
      ';return {fire:(v)=>'+callbacks.fire+',weather:(d)=>'+callbacks.weather+'};';
    const hud=new Function('$',factory)(id=>document.getElementById(id));
    const bits=value=>{
      const buffer=new ArrayBuffer(8),view=new DataView(buffer);
      view.setFloat64(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const samples=inputs.map(input=>{
      document.body.classList.toggle('aiming',input.scoped);
      hud.fire(input.fire);hud.weather(input.weather);
      const radius=parseFloat(document.body.style.getPropertyValue('--scope-r'));
      const blur=fire.style.backdropFilter?parseFloat(fire.style.backdropFilter.slice(5)):0;
      let gradient=null;
      if(input.weather>0) {
        const values=[...weather.style.background.matchAll(/(-?(?:\d+(?:\.\d*)?|\.\d+))(vmin|%)/g)]
          .slice(-3).map(match=>Number(match[1]));
        if(values.length!==3)throw new Error('Unexpected original gradient: '+weather.style.background);
        gradient=input.scoped?{inner:values[1],innerBits:bits(values[1]),outer:values[2]}:
          {stops:[values[1]/100,values[2]/100]};
      }
      return {...input,fireBits:bits(input.fire),weatherBits:bits(input.weather),radius,radiusBits:bits(radius),
        blur,blurBits:bits(blur),gradient};
    });
    const programs=commands.map(program=>{
      let gradientScoped=false;
      return program.map(input=>{
        document.body.classList.toggle('aiming',input.scoped);
        hud.fire(input.fire);hud.weather(input.weather);
        if(input.weather>0)gradientScoped=input.scoped;
        const background=weather.style.background;
        const values=[...background.matchAll(/(-?(?:\d+(?:\.\d*)?|\.\d+))(vmin|%)/g)]
          .slice(-3).map(match=>Number(match[1]));
        if(values.length!==3)throw new Error('Unexpected original retained gradient: '+background);
        return {...input,radius:parseFloat(document.body.style.getPropertyValue('--scope-r')),
          gradient:{scoped:gradientScoped,background,
            stops:gradientScoped?[values[1],values[2]]:[values[1]/100,values[2]/100]}};
      });
    });
    return {samples,programs};
  },{definitions,callbacks,inputs,commands});
  for(const [path,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during scope value capture: '+path);
  if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
    throw new Error('Scope values generator changed during capture');
  await writeFixtureJson(join(root,'tests/fixtures/scope_values.json'),{formatVersion:1,
    source:{inputs:{[generator]:generatorHash},sourceInputs},browser:browser.version(),...capture});
  console.log('SCOPE_VALUES_REFERENCES_PASS samples='+capture.samples.length+' programs='+capture.programs.length);
} finally {await browser.close();}
