import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/css/style.css','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const html=await readFile(join(source,'public/index.html'),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const cases=[],rules={};
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[200,400],[320,568],[568,320],[500,500],[550,800],[900,650],[1024,768],[1600,1200]]){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,html})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-screen"><div class="prologue-narrative-box"></div></div>';
      const source=new DOMParser().parseFromString(html,'text/html');
      const original=source.querySelector('#prologueNarrativeBox .prologue-box-header');
      if(!original||!original.querySelector('#prologueBoxBadge')||!original.querySelector('#prologueBoxTitle'))
        throw new Error('Original cinematic header changed');
      document.querySelector('.prologue-narrative-box').append(original.cloneNode(true));
      const marker=document.createElement('div');
      marker.className='pcs-chapter-mark';
      marker.innerHTML='<span class="pcs-badge">badge</span><span class="pcs-title-inline">title</span>';
      document.querySelector('.prologue-narrative-box').append(marker);
      const header=document.querySelector('.prologue-box-header'),style=getComputedStyle(header);
      const rgba=value=>{const numbers=value.match(/[\d.]+/g)?.map(Number);if(!numbers||numbers.length<3)throw new Error('Unsupported header color: '+value);return [numbers[0]/255,numbers[1]/255,numbers[2]/255,numbers[3]??1];};
      const fontRule=selector=>{
        const rule=[...document.styleSheets[0].cssRules].find(item=>item.selectorText===selector);
        const value=rule?.style.fontSize;
        const match=value?.match(/^clamp\(([\d.]+)px,\s*([\d.]+)px \+ ([\d.]+)vmin,\s*([\d.]+)px\)$/);
        if(!match)throw new Error('Unsupported original header font rule: '+value);
        return {min:Number(match[1]),vmin:Number(match[3]),offset:Number(match[2]),max:Number(match[4])};
      };
      return {padding:{top:parseFloat(style.paddingTop),right:parseFloat(style.paddingRight),
        bottom:parseFloat(style.paddingBottom),left:parseFloat(style.paddingLeft)},
        borderWidth:parseFloat(style.borderBottomWidth),background:rgba(style.backgroundColor),border:rgba(style.borderBottomColor),
        colours:{badge:rgba(getComputedStyle(header.querySelector('#prologueBoxBadge')).color),
          title:rgba(getComputedStyle(header.querySelector('#prologueBoxTitle')).color),
          sectionBadge:rgba(getComputedStyle(marker.querySelector('.pcs-badge')).color),
          sectionTitle:rgba(getComputedStyle(marker.querySelector('.pcs-title-inline')).color)},
        fonts:{badge:fontRule('.prologue-box-badge'),title:fontRule('.prologue-box-title'),section:fontRule('.pcs-chapter-mark')},
        fontSizes:{badge:parseFloat(getComputedStyle(header.querySelector('#prologueBoxBadge')).fontSize),
          title:parseFloat(getComputedStyle(header.querySelector('#prologueBoxTitle')).fontSize),
          section:parseFloat(getComputedStyle(marker.querySelector('.pcs-badge')).fontSize),
          sectionTitle:parseFloat(getComputedStyle(marker.querySelector('.pcs-title-inline')).fontSize)}};
    },{css,html});
    const mode=width>height?'landscape':'portrait';
    if(rules[mode]&&JSON.stringify(rules[mode])!==JSON.stringify(sample.padding))throw new Error('Original header padding varies within '+mode);
    rules[mode]=sample.padding;
    for(const key of ['borderWidth','background','border','fonts','colours']){
      if(rules[key]!==undefined&&JSON.stringify(rules[key])!==JSON.stringify(sample[key]))throw new Error('Original header style varies: '+key);
      rules[key]=sample[key];
    }
    cases.push({size:[width,height],...sample});
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_header_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_header.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_header.json'),{...base,browser:browser.version(),cases});
console.log('CAMPAIGN_HEADER_CAPTURE_PASS cases='+cases.length);
