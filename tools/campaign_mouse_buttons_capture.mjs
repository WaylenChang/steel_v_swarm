import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original cinematic input changed: '+path);
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const methods=['bindEvents','startLongPress','cancelLongPress'].map(name=>PrologueIntroController.prototype[name].toString());
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const cases=[
  ['right', [['down','right'],['up','right']]],
  ['middle', [['down','middle'],['up','middle']]],
  ['back', [['down','back'],['up','back']]],
  ['forward', [['down','forward'],['up','forward']]],
  ['side_then_left', [['down','back'],['down','left'],['up','back'],['up','left']]],
  ['wheel_during_hold', [['down','left'],['wheel',null],['up','left']]],
  ['left_then_right', [['down','left'],['down','right'],['up','left'],['up','right']]],
  ['right_then_left', [['down','right'],['down','left'],['up','right'],['up','left']]],
];
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const programs=[];
try{
  for(const [name,operations] of cases){
    const page=await browser.newPage({viewport:{width:320,height:240},deviceScaleFactor:1});
    await page.setContent('<div id="root" style="position:fixed;inset:0"></div>');
    await page.evaluate(methods=>{
      const Controller=new Function('return class {'+methods.join('\n')+'}')();
      const root=document.querySelector('#root');
      const context=Object.assign(new Controller(),{root,viewport:null,holdIndicator:null,holdCircle:null,
        holdRaf:null,holdStart:0,lastTapTime:0,destroyed:false,trySkip(){}});
      window.requestAnimationFrame=()=>1;
      window.cancelAnimationFrame=()=>{};
      context.bindEvents();
      const events=[];
      for(const type of ['pointerdown','pointerup','pointercancel'])
        window.addEventListener(type,event=>events.push({type,button:event.button,buttons:event.buttons}));
      window.sample=()=>({holding:context.holdRaf!==null,holdStart:context.holdStart,events:events.splice(0)});
    },methods);
    await page.mouse.move(100,100);
    const protocol=await page.context().newCDPSession(page);
    let extraMask=0;
    const frames=[];
    for(const [action,button] of operations){
      if(action==='wheel')await page.mouse.wheel(0,120);
      else if(button==='back'||button==='forward'||name==='side_then_left'){
        const mask={left:1,right:2,middle:4,back:8,forward:16}[button];
        extraMask=action==='down'?extraMask|mask:extraMask&~mask;
        await protocol.send('Input.dispatchMouseEvent',{type:action==='down'?'mousePressed':'mouseReleased',
          x:100,y:100,button,buttons:extraMask,clickCount:1});
      }
      else await page.mouse[action]({button});
      frames.push({action,button,...await page.evaluate(()=>window.sample())});
    }
    programs.push({name,frames});
    await page.close();
  }
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original cinematic input changed during capture: '+path);
const inputs={};
for(const path of ['tools/campaign_mouse_buttons_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_mouse_buttons.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('CAMPAIGN_MOUSE_BUTTONS_CAPTURE_PASS programs='+programs.length);
