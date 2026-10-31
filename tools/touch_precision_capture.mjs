import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {encodeSourceNumericPart as encode} from './source_numeric_transfer.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/mobile.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  assert.equal(hash(bytes),provenance.inputs[path],'Original touch input: '+path);
  sourceInputs[path]=hash(bytes);
}
const {grabMethod,grabFn,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const mobile=(await readFile(join(source,'public/js/mobile.js'),'utf8')).replace(/\r\n?/g,'\n');
const rules=new Function(grabConst(mobile,'LOOK')+';return LOOK;')();
const defaults=new Function(grabConst(mobile,'TOUCH')+';return TOUCH;')();
const body=mobile.slice(mobile.indexOf('export class TouchControls'));
const methods=['constructor','_bindLook','_bindSticks','_bindStick','_stickPaint','_bindButtons','_tapNear','_tapOk',
  '_dropTap','_tickTap','_setLookFire','_blocked','tick','_tickLookFire','syncBlocked','reset','_haptic'];
const original='let _active=null;\n'+grabFn(mobile,'capture')+'\nclass OriginalTouch {\n'+
  methods.map(name=>grabMethod(body,name)).join('\n')+
  '\n_bindRotateHint() {}\nsetKind() {}\n_syncGyroBtn() {}\n_local() {return false;}\n}';
const point=values=>values.map(Math.fround),sticks=[];
for(const boundary of [rules.STICK_DEAD,rules.STICK_DEAD+rules.SPRINT_MAG*(1-rules.STICK_DEAD),1])
  for(let angle=0;angle<96;angle++)for(const offset of [-.000005,0,.000005]) {
    const radius=70*boundary+offset,a=angle/96*Math.PI*2;
    sticks.push({name:'boundary:'+boundary+':'+angle+':'+offset,point:point([Math.cos(a)*radius,Math.sin(a)*radius]),
      centre:[0,0],radius:70,sensitivity:[.4,1,2.5][angle%3],delta:[0,.016,.03333333333333333][angle%3]});
  }
let seed=0x51de;
const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
for(let index=0;index<128;index++) {
  const centre=point([random()*10000-5000,random()*10000-5000]);
  sticks.push({name:'native:'+index,point:point(centre.map(value=>value+random()*200-100)),centre,radius:70,
    sensitivity:[.4,1,2.5][index%3],delta:.016});
}
const gestures=[],tap=[{kind:'lookDown',at:1000,point:[0,0]},{kind:'up',at:1020,point:[0,0]}];
for(const p of [[16,0],[16,.001],[15.999999046325684,.002],[7.999999523162842,.002],[8,0],
  [8,.001],[-16,.001],[.001,16],[1000,1000]]) {
  const target=point(p),label=target.join(',');
  gestures.push({name:'button-release:'+label,steps:[{kind:'button',action:'reload',at:1000,point:[0,0]},
    {kind:'up',at:1020,point:target}]});
  gestures.push({name:'button-return:'+label,steps:[{kind:'button',action:'reload',at:1000,point:[0,0]},
    {kind:'move',at:1010,point:target},{kind:'up',at:1020,point:[0,0]}]});
  gestures.push({name:'tap-release:'+label,steps:[{kind:'lookDown',at:1000,point:[0,0]},
    {kind:'up',at:1020,point:target},{kind:'lookDown',at:1100,point:[0,0]},{kind:'tick',at:1230,delta:.016}]});
  gestures.push({name:'tap-near:'+label,steps:[...tap,{kind:'lookDown',at:1100,point:target},
    {kind:'tick',at:1230,delta:.016}]});
  gestures.push({name:'drag-fire:'+label,steps:[...tap,{kind:'lookDown',at:1100,point:[0,0]},
    {kind:'move',at:1110,point:target},{kind:'up',at:1120,point:target}]});
}
for(const [name,steps]of [
  ['cancel',[{kind:'button',action:'reload',at:1000,point:[0,0]},{kind:'up',at:1020,point:[0,0],cancel:true}]],
  ['hold',[{kind:'button',action:'aim',at:1000,point:[0,0]},{kind:'move',at:1010,point:[16,.001]},
    {kind:'up',at:1020,point:[16,.001]}]],
  ['blocked',[...tap,{kind:'lookDown',at:1100,point:[0,0]},{kind:'tick',at:1230,delta:.016},
    {kind:'blocked',at:1240,value:true},{kind:'reset',at:1241}]]])gestures.push({name,steps});

function replay(original,rules,defaults,sticks,gestures,encode) {
  let now=1000,events=[],elements={},centre=[0,0],radius=70;
  const element=id=>elements[id]??={dataset:{act:id},style:{},classList:{contains:()=>false,add(){},remove(){},toggle(){}},
    closest(){return this;},setPointerCapture(){},getBoundingClientRect:()=>({left:centre[0]-radius,top:centre[1]-radius,width:radius*2,height:radius*2}),
    addEventListener(){}};
  const document={getElementById:element,querySelectorAll:()=>[],body:{classList:{toggle(){}}},addEventListener(){}};
  const TOUCH={...defaults};
  const Original=new Function('LOOK','TOUCH','document','performance','navigator','Gyro','setTimeout',
    original+';return OriginalTouch;')(rules,TOUCH,document,{now:()=>now},
      {vibrate:milliseconds=>events.push({type:'haptic',milliseconds})},class {},callback=>{callback();return 1;});
  const make=sensitivity=>{
    now=1000;events=[];elements={};TOUCH.lookSens=sensitivity;
    return new Original({paused:false,shopOpen:false,_gameOver:false,
      _cmd:(action,on)=>events.push({type:'command',action,on}),
      _applyLook:(x,y)=>events.push({type:'look',source:encode([x,y])})});
  };
  const event=(id,p=[0,0],action='',cancel=false)=>({pointerId:id,clientX:p[0],clientY:p[1],
    type:cancel?'pointercancel':'pointerup',target:element(action),preventDefault(){},stopPropagation(){}});
  const state=original=>({lookId:original._lookId??-1,fireArm:original._fireArm,lookFire:original._lookFire,
    clocks:encode([original._tapAt,original._downAt]),
    scalars:encode([original.moveStick.x,original.moveStick.y,original.moveStick.mag,
      original.lookStick.x,original.lookStick.y,original.lookStick.mag]),
    axis:encode([original.axis.r,-original.axis.f]),held:Object.fromEntries(original._held),taps:[...original._tap.keys()]});
  const output={sticks:[],gestures:[]};
  for(const input of sticks) {
    centre=input.centre;radius=input.radius;
    const original=make(input.sensitivity);
    original.moveStick.onDown(event(1,input.point));original.lookStick.onDown(event(2,input.point));original.tick(input.delta);
    const active={events:events.slice(),state:state(original)};
    events=[];original.moveStick.onUp(event(1));original.lookStick.onUp(event(2));original.reset();original.tick(.016);
    output.sticks.push({active,released:{events:events.slice(),state:state(original)}});
  }
  centre=[0,0];radius=70;
  for(const input of gestures) {
    const original=make(1),frames=[];
    for(const step of input.steps) {
      now=step.at;events=[];const e=event(1,step.point,step.action,step.cancel);
      if(step.kind==='lookDown')original._onLookDown(e);
      else if(step.kind==='button')original._onBtnDown(e);
      else if(step.kind==='move') {original._onLookMove(e);original._onBtnMove(e);}
      else if(step.kind==='up') {original._onLookUp(e);original._onBtnUp(e);}
      else if(step.kind==='tick')original.tick(step.delta);
      else if(step.kind==='reset')original.reset();
      else if(step.kind==='blocked') {original.client.paused=step.value;original.syncBlocked();}
      frames.push({events:events.slice(),state:state(original)});
    }
    output.gestures.push(frames);
  }
  return output;
}

const expected=replay(original,rules,defaults,sticks,gestures,encode);
const producers=['tools/touch_precision_capture.mjs','tools/source_numeric_transfer.mjs','tools/fixture_json.mjs'];
const inputs=Object.fromEntries(await Promise.all(producers.map(async path=>
  [path,hash((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'))])));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original touch precision requires Chromium');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const actual=await (await browser.newPage()).evaluate(({original,rules,defaults,sticks,gestures,run,codec})=>
    new Function('return ('+run+');')()(original,rules,defaults,sticks,gestures,new Function('return ('+codec+');')()),
    {original,rules,defaults,sticks,gestures,run:replay.toString(),codec:encode.toString()});
  assert.deepEqual(actual,expected,'Original Node/Chromium touch state, event order and scalar bits');
  for(const [path,digest]of Object.entries(sourceInputs))
    assert.equal(hash(await readFile(join(source,path))),digest,'Source changed during touch capture: '+path);
  for(const [path,digest]of Object.entries(inputs))
    assert.equal(hash((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),digest,'Producer changed during touch capture: '+path);
  const encodedSticks=sticks.map(input=>({name:input.name,values:encode([...input.point,...input.centre,input.radius,input.sensitivity,input.delta])}));
  const encodedGestures=gestures.map(input=>({name:input.name,steps:input.steps.map(step=>({...step,
    point:undefined,at:undefined,delta:undefined,values:encode([...(step.point??[0,0]),step.at,step.delta??0])}))}));
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/touch_precision.json'),{formatVersion:1,scope:'original-touch-native-boundary-precision',
    source:{inputs,sourceInputs,chromiumVersion:browser.version()},ruleNames:Object.keys(rules),ruleValues:encode(Object.values(rules)),
    sticks:encodedSticks,gestures:encodedGestures,expected:actual});
  console.log('TOUCH_PRECISION_CAPTURE_PASS '+JSON.stringify({sticks:sticks.length,gestures:gestures.length}));
} finally {await browser.close();}
