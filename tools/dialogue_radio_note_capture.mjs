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
const cases=[
  {title:'兩張報價單',note:'蜂群前線砲塔全數失去訊號。'},
  {title:'<標題> & "測試"',note:'訊息 <安全> & "原文"'},
  {title:'',note:'只有說明'},
  {title:'只有標題',note:''}
];
let programs,rules;
try{
  const page=await browser.newPage({viewport:{width:1024,height:768}});
  ({programs,rules}=await page.evaluate(({css,method,helpers,characters,sides,cases})=>{
    const style=document.createElement('style');style.textContent=css;document.head.append(style);
    const create=new Function('CHARACTERS','SIDES',`${helpers}\nconst artAvatarURL=()=>''; return ({${method}}).radio;`);
    const radio=create(characters,sides),programs=[];let rules;
    for(const item of cases){
      const root=document.createElement('div');root.className='dlg-layer';document.body.append(root);
      const ctx={root,bar:null,artMode:'char',_foe(){return 'SWARM'},clear(){this.bar?.remove();this.bar=null},
        _after(_ms,fn){this.next=fn},_fadeOut(el){el.remove();this.bar=null}};
      const scene={...item,lines:[{ch:'t06',t:'first'},{ch:'s01',t:'second'},{ch:'m01',t:'third'}]};
      radio.call(ctx,scene);
      const frames=[];
      for(let i=0;i<scene.lines.length;i++){
        const note=ctx.bar.querySelector('.dlg-note'),title=note.querySelector('b'),description=note.querySelector('span');
        const row=getComputedStyle(note),a=getComputedStyle(title),b=getComputedStyle(description);
        const color=text=>{const parts=text.match(/[\d.]+/g).map(Number);return [...parts.slice(0,3).map(x=>x/255),parts.length>3?parts[3]:1];};
        const sample={title:title.textContent,note:description.textContent,combined:note.textContent,titleColor:color(a.color),noteColor:color(b.color),
          fontSize:parseFloat(row.fontSize),gap:parseFloat(row.columnGap)};
        if(!rules)rules={fontSize:sample.fontSize,gap:sample.gap,noteColor:sample.noteColor};
        frames.push({speaker:scene.lines[i].ch,...sample});
        if(i+1<scene.lines.length)ctx.next();
      }
      programs.push({...item,frames});root.remove();
    }
    style.remove();return {programs,rules};
  },{css,method:Dialogue.prototype.radio.toString(),helpers,characters,sides,cases}));
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Source changed during capture: '+path);
const inputs={};for(const path of ['tools/dialogue_radio_note_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/dialogue_radio_note.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/dialogue_radio_note.json'),{...base,browser:browser.version(),programs});
console.log('DIALOGUE_RADIO_NOTE_CAPTURE_PASS programs='+programs.length);
