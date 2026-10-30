import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const paths=['public/css/style.css','public/js/dialogue.js','public/js/data.js'],sourceInputs={};
for(const path of paths){
  const bytes=await readFile(join(source,path));sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original source changed: '+path);
}
const script=await readFile(join(source,paths[1]),'utf8');
const helpers=script.slice(script.indexOf('const lineMs ='),script.indexOf('export class Dialogue'));
if(!helpers.startsWith('const lineMs =')||!helpers.includes('const facOf ='))throw new Error('Original helper section changed');
const css=await readFile(join(source,paths[0]),'utf8');
const {Dialogue}=await import(pathToFileURL(join(source,paths[1])).href);
const {CHARACTERS,SIDES}=await import(pathToFileURL(join(source,paths[2])).href);
const characters=Object.fromEntries(['t06','s01','m01'].map(id=>[id,CHARACTERS[id]]));
const sides=Object.fromEntries(['STEEL','SWARM'].map(side=>[side,{color:SIDES[side].color}]));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of [[320,568],[720,900],[721,900],[1440,900]]){
    await page.setViewportSize({width,height});
    const frames=await page.evaluate(({css,method,helpers,characters,sides})=>{
      const style=document.createElement('style');style.textContent=css;document.head.append(style);
      const create=new Function('CHARACTERS','SIDES',`${helpers}\nconst artAvatarURL=()=>''; return ({${method}}).radio;`);
      const radio=create(characters,sides);
      const root=document.createElement('div');root.className='dlg-layer';document.body.append(root);
      const ctx={root,bar:null,artMode:'char',_foe(){return 'SWARM'},clear(){this.bar?.remove();this.bar=null},
        _after(_ms,fn){this.next=fn},_fadeOut(el){el.remove();this.bar=null}};
      const lines=[{ch:'t06',t:'普通訊息'},{ch:'s01',t:'[b]文字[/b] <tag> & "引號"'},{ch:'m01',t:'😃 🚁'}, {ch:'t06',t:''}];
      radio.call(ctx,{title:'',note:'',lines});
      const frames=[];
      for(let i=0;i<lines.length;i++){
        const text=ctx.bar.querySelector('.dlg-txt'),speaker=text.querySelector('.dlg-who'),line=text.querySelector('.dlg-line');
        const a=getComputedStyle(speaker),b=getComputedStyle(line),parent=getComputedStyle(text);
        const color=value=>{const p=value.match(/[\d.]+/g).map(Number);return [...p.slice(0,3).map(x=>x/255),p.length>3?p[3]:1];};
        frames.push({speaker:lines[i].ch,input:lines[i].t,name:speaker.textContent,text:line.textContent,
          speakerFont:parseFloat(a.fontSize),speakerColor:color(a.color),lineFont:parseFloat(b.fontSize),
          lineColor:color(b.color),lineHeight:parseFloat(b.lineHeight),gap:parseFloat(parent.rowGap)});
        if(i+1<lines.length)ctx.next();
      }
      root.remove();style.remove();return frames;
    },{css,method:Dialogue.prototype.radio.toString(),helpers,characters,sides});
    programs.push({viewport:[width,height],frames});
  }
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Source changed during capture: '+path);
const breakpoint=css.match(/@media\s*\(max-width:\s*([\d.]+)px\)\s*\{\s*\.dlg-bar\s*\{/);
if(!breakpoint)throw new Error('Unsupported original radio breakpoint');
const mobile=programs.find(p=>p.viewport[0]===Number(breakpoint[1])).frames[0];
const desktop=programs.find(p=>p.viewport[0]===Number(breakpoint[1])+1).frames[0];
if(mobile.speakerFont!==desktop.speakerFont||mobile.gap!==desktop.gap||JSON.stringify(mobile.lineColor)!==JSON.stringify(desktop.lineColor))
  throw new Error('Original radio text shared styles vary across the breakpoint');
const rules={mobileMaxWidth:Number(breakpoint[1]),speakerFont:desktop.speakerFont,gap:desktop.gap,
  lineColor:desktop.lineColor,mobileLineFont:mobile.lineFont,desktopLineFont:desktop.lineFont,
  lineHeightRatio:desktop.lineHeight/desktop.lineFont};
const inputs={};for(const path of ['tools/dialogue_radio_text_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/dialogue_radio_text.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/dialogue_radio_text.json'),{...base,browser:browser.version(),programs});
console.log('DIALOGUE_RADIO_TEXT_CAPTURE_PASS programs='+programs.length);
