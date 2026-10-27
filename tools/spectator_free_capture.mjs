import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_free_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const balance=JSON.parse(await readFile(join(root,'data/balance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const expression=name=>{
  const match=new RegExp('export const '+name+' = \\(([^)]*)\\) =>\\s*([^;]+);').exec(data);
  if(!match)throw new Error('Missing source helper '+name);
  return {parameters:match[1],body:match[2]};
};
const wrap=/export const wrapPi = \(a\) => \{([\s\S]*?)\n\};/.exec(data);
if(!wrap)throw new Error('Missing source wrapPi');
const program={cameraRules:grabConst(data,'SPEC_CAM'),
  methods:['_updateSpectator','_specRoster','_specFollow','_specSetView'].map(name=>grabMethod(game,name)),
  locked:expression('specViewLocked'),friction:expression('frictionFPS'),lerp:expression('lerpFPS'),
  angle:expression('camAngleStep'),wrap:wrap[1]};
const tiny=2**-15,step=2**-13;
const axis=(f=0,r=0,mag=0,boost=false)=>({f,r,mag,boost});
const move=(count,fields)=>Array.from({length:count},()=>({advance:1/240,...fields}));
const actor=(pid,position)=>({pid,side:'STEEL',hero:true,act:true,dead:false,ch:'',ry:0,heroY:0,position});
const tieActors=[actor('1',[1024+step,10,0]),actor('2',[1024,10,0])];
const sequences=[
  {name:'small-analog-follow-tie',position:[1024,10,0],steps:[
    ...tieActors.map(add=>({add})),...move(4,{axis:axis(0,tiny,tiny)}),{follow:0},{advance:0},{select:'god'},
    ...move(20,{axis:axis(0,-tiny,tiny)})]},
  {name:'small-analog-mode-tie',position:[1024,10,0],steps:[
    ...tieActors.map(add=>({add})),...move(4,{axis:axis(0,tiny,tiny)}),{select:'orbit'},{advance:0}]},
  {name:'diagonal-boost-reversal',position:[-2048,15,1024],steps:[
    {yaw:.7},...move(70,{axis:axis(1,1,Math.SQRT2,true)}),
    {yaw:-1.2},...move(40,{axis:axis(-.5,.25,1,false)}),{advance:0,axis:axis(0,0,0)}]},
  {name:'vertical-and-clamps',position:[0,2048,0],steps:[
    ...Array.from({length:80},()=>({advance:2**-21,up:true})),
    {advance:.1,up:true,down:true},{advance:.2,down:true},
    {surface:2200,ceiling:2100,advance:0},{surface:0,ceiling:2100,advance:0},
    {surface:0,ceiling:2100,advance:.25,up:true}]},
  {name:'orbit-to-free-continuity',position:[1024,30,0],steps:[
    {add:actor('1',[1024,30,0])},{select:'orbit'},{advance:0},
    {update:{pid:'1',position:[1024+step,30,0]}},...move(32,{axis:axis()}),
    {select:'god'},...move(40,{axis:axis(0,tiny,tiny)})]},
];
for(const sequence of sequences){
  const points=[sequence.position,...sequence.steps.flatMap(row=>[row.add?.position,row.update?.position].filter(Boolean))];
  for(const point of points)if(!point.every(value=>Object.is(value,Math.fround(value))))
    throw new Error('Controlled positions must be representable by native Vector3');
}
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let capture,runtime,cameraRules;
try{
  const page=await browser.newPage();
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.origin!=='http://source.invalid')return route.abort();
    if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><body></body></html>'});
    if(url.pathname==='/three.module.js')return route.fulfill({contentType:'text/javascript',body:contents['out/forest_review/three.module.js']});
    return route.abort();
  });
  await page.goto('http://source.invalid/');
  ({capture,runtime,cameraRules}=await page.evaluate(async({program,sequences,profile})=>{
    const THREE=await import('/three.module.js');
    const rules=new Function(program.cameraRules+'\nreturn SPEC_CAM;')();
    const locked=new Function('SPEC_CAM',program.locked.parameters,'return '+program.locked.body+';').bind(null,rules);
    const friction=new Function(program.friction.parameters,'return '+program.friction.body+';');
    const lerp=new Function('frictionFPS',program.lerp.parameters,'return '+program.lerp.body+';').bind(null,friction);
    const wrap=new Function('a',program.wrap);
    const angle=new Function('wrapPi','lerpFPS',program.angle.parameters,'return '+program.angle.body+';').bind(null,wrap,lerp);
    const characters={},sides={STEEL:{hero:'robot',name:'controlled'}};
    const height=()=>profile.height,view=(_kind,_ch,flying)=>flying?profile.air:profile.ground;
    const proto=new Function('SPEC_CAM','specViewLocked','lerpFPS','camAngleStep','CHARACTERS','SIDES','heroTargetH','heroView',
      'return ({'+program.methods.join(',\n')+'});')(rules,locked,lerp,angle,characters,sides,height,view);
    proto._specName=actor=>actor?.pid||'';
    const bits=(value,wide)=>{
      const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const capture=sequences.map(sequence=>{
      let surface=-1000,ceiling=10000,axis={f:0,r:0,mag:0,boost:false};
      const ents=new Map();
      const context=Object.assign(Object.create(proto),{side:null,pos:new THREE.Vector3(...sequence.position),yaw:0,pitch:-.9,
        camera:new THREE.PerspectiveCamera(68,1,.1,10000),keys:{},ents,hud:{feed(){}},_specView:'god',_specPid:null,
        _specAnchor:new THREE.Vector3(),_specAnchorOk:false,_specYaw:0,_specHid:null,_specFov:68,
        _moveAxis:()=>axis,_surf:()=>surface,_ceilY:()=>ceiling,_cameraPullSegment:()=>{}});
      const frames=[];
      for(const operation of sequence.steps){
        if(operation.add){const row=operation.add;ents.set(row.pid,{...row,mesh:{position:new THREE.Vector3(...row.position),visible:true}});}
        if(operation.update){const row=operation.update;ents.get(row.pid).mesh.position.fromArray(row.position);}
        if(Object.hasOwn(operation,'surface'))surface=operation.surface;
        if(Object.hasOwn(operation,'ceiling'))ceiling=operation.ceiling;
        if(Object.hasOwn(operation,'yaw'))context.yaw=operation.yaw;
        if(Object.hasOwn(operation,'select'))context._specSetView(operation.select);
        if(Object.hasOwn(operation,'follow'))context._specFollow(operation.follow);
        if(Object.hasOwn(operation,'advance')){
          axis=operation.axis||{f:0,r:0,mag:0,boost:false};
          context.keys={Space:!!operation.up,KeyC:!!operation.down,ControlLeft:!!operation.ctrl};
          context._updateSpectator(operation.advance);
        }
        const position=context.pos.toArray();
        frames.push({operation,deltaBits:Object.hasOwn(operation,'advance')?bits(operation.advance,true):null,
          yawBits:Object.hasOwn(operation,'yaw')?bits(operation.yaw,true):null,
          magBits:operation.axis?bits(operation.axis.mag,true):null,mode:context._specView,pid:context._specPid||'',
          positionBits:position.map(value=>bits(value,true)),positionFloat32Bits:position.map(value=>bits(value,false))});
      }
      return {name:sequence.name,position:sequence.position,frames};
    });
    return {capture,runtime:{userAgent:navigator.userAgent},cameraRules:rules};
  },{program,sequences,profile:balance.spectator.fallbacks.STEEL}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during spectator free-camera capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator free-camera generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_free.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,cameraRules,
  profile:balance.spectator.fallbacks.STEEL,sequences:capture});
console.log('SPECTATOR_FREE_REFERENCES_PASS sequences='+capture.length+' frames='+capture.reduce((n,row)=>n+row.frames.length,0));
