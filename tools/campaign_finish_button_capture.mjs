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
for(const path of ['public/css/style.css','public/js/prologue.js','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];let rules;
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[640,360],[320,568],[500,500]]){
    await page.setViewportSize({width,height});
    for(const [contentWidth,contentHeight] of [[30,20],[120,20],[160,32]]){
      const sample=await page.evaluate(({css,contentWidth,contentHeight})=>{
        document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
        document.body.innerHTML=`<div class="prologue-crawl-end" style="width:300px"><button class="btn big steel-btn prologue-finish-btn"><span style="display:block;width:${contentWidth}px;height:${contentHeight}px;background:rgb(255,0,255)"></span></button></div>`;
        const button=document.querySelector('button'),content=button.firstElementChild,style=getComputedStyle(button);
        const sides=['top','right','bottom','left'];
        const rules={padding:Object.fromEntries(sides.map(side=>[side,parseFloat(style.getPropertyValue('padding-'+side))])),
          border:Object.fromEntries(sides.map(side=>[side,parseFloat(style.getPropertyValue('border-'+side+'-width'))])),
          fontSize:parseFloat(style.fontSize),letterSpacing:parseFloat(style.letterSpacing),cursor:style.cursor};
        const box=button.getBoundingClientRect(),inside=content.getBoundingClientRect();
        return {rules,button:[box.width,box.height],content:[inside.left-box.left,inside.top-box.top,inside.width,inside.height]};
      },{css,contentWidth,contentHeight});
      if(rules&&JSON.stringify(rules)!==JSON.stringify(sample.rules))throw new Error('Original finish-button rules vary by viewport');
      rules=sample.rules;
      programs.push({size:[width,height],contentSize:[contentWidth,contentHeight],...sample});
    }
  }
}finally{await browser.close();}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_finish_button_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_finish_button.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/campaign_finish_button.json'),{...base,browser:browser.version(),programs});
console.log('CAMPAIGN_FINISH_BUTTON_CAPTURE_PASS programs='+programs.length);
