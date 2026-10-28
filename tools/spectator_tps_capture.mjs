import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_tps_capture.mjs';
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
const method=grabMethod(game,'_updateSpectator');
const anchorStart=method.indexOf('      if (specViewLocked(view) || !this._specAnchorOk');
const anchorEnd=method.indexOf('      const a = this._specAnchor;',anchorStart);
const start=method.indexOf("        if (view === 'tps') this.yaw = this._specYaw;");
const end=method.indexOf('\n      }\n    } else {',start);
const locked=/export const specViewLocked = \(view\) =>\s*([^;]+);/.exec(data);
const friction=/export const frictionFPS = \(k, dt\) =>\s*([^;]+);/.exec(data);
const lerp=/export const lerpFPS = \(k, dt\) =>\s*([^;]+);/.exec(data);
if(anchorStart<0||anchorEnd<0||start<0||end<0||!locked||!friction||!lerp)
  throw new Error('Missing original spectator third-person camera seams');
const program={cameraRules:grabConst(data,'SPEC_CAM'),anchor:method.slice(anchorStart,anchorEnd),
  branch:method.slice(start,end),pull:grabMethod(game,'_cameraPullSegment'),
  locked:locked[1],friction:friction[1],lerp:lerp[1]};
const actors=['s01','s03','t01','t06','t09','m01',''].map(character=>({
  character,profile:character?balance.spectator.profiles[character]:balance.spectator.fallbacks.STEEL,
}));
if(actors.some(row=>!row.profile))throw new Error('Missing controlled spectator profile');
const points=[[12,5,-9],[1024,-1024,-1024],[.5,0,-.5]];
for(const point of points)if(!point.every(value=>Object.is(value,Math.fround(value))))
  throw new Error('Input positions must be exactly representable by native Vector3');
const angles=[0,.7,-1.2,Math.PI/2,20000.12345],pitches=[0,-.25,.7];
const cases=[];
for(const actor of actors)for(const point of points)for(const yaw of angles)for(const pitch of pitches)for(const view of ['tps','orbit'])
  cases.push({kind:'clear',character:actor.character,point,yaw,pitch,view,hit:null,ridge:false});
for(const yaw of [0,.7])for(const pitch of [0,-.25])for(const hit of [null,0,4])for(const ridge of [false,true])
  cases.push({kind:'clip',character:'s01',point:[0,10,0],yaw,pitch,view:'orbit',hit,ridge});
const sequence={character:'s01',initial:[1024,10,0],point:[1024+2**-13,10,0],yaw:.7,pitch:-.25,view:'orbit',
  steps:Array.from({length:48},()=>({delta:1/240}))};
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
  ({capture,runtime,cameraRules}=await page.evaluate(async({program,actors,cases,sequence})=>{
    const THREE=await import('/three.module.js');
    const rules=new Function(program.cameraRules+'\nreturn SPEC_CAM;')();
    const locked=new Function('SPEC_CAM','return (view)=>'+program.locked+';')(rules);
    const friction=new Function('return (k,dt)=>'+program.friction+';')();
    const lerp=new Function('frictionFPS','return (k,dt)=>'+program.lerp+';')(friction);
    const updateAnchor=new Function('specViewLocked','SPEC_CAM','lerpFPS','view','p','dt',program.anchor);
    const advance=new Function('SPEC_CAM','view','h','a',program.branch);
    const pull=new Function('return ({'+program.pull+'});')()._cameraPullSegment;
    const bits=(value,wide)=>{
      const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const vectorBits=(values,wide)=>values.map(value=>bits(value,wide));
    const render=(row,anchor)=>{
      const profile=actors.find(actor=>actor.character===row.character).profile;
      let inPull=false,samples=0,aim,before,pulled;
      const context={_specYaw:row.yaw,yaw:row.yaw,pitch:row.pitch,camera:{position:new THREE.Vector3()},
        _blockerHitT:()=>row.hit,_surf:(_x,z,_y)=>{if(inPull)samples++;return row.ridge&&z>4&&z<9?20:-10000;}};
      context._cameraPullSegment=(x,y,z)=>{
        aim=[x,y,z];before=context.camera.position.toArray();inPull=true;
        pull.call(context,x,y,z);inPull=false;pulled=context.camera.position.toArray();
      };
      advance.call(context,rules,row.view,profile.height,anchor);
      return {...row,yawBits:bits(row.yaw,true),pitchBits:bits(row.pitch,true),
        aimBits:vectorBits(aim,true),aimFloat32Bits:vectorBits(aim,false),
        beforeBits:vectorBits(before,true),beforeFloat32Bits:vectorBits(before,false),
        pulledBits:vectorBits(pulled,true),pulledFloat32Bits:vectorBits(pulled,false),
        finalFloat32Bits:vectorBits(context.camera.position.toArray(),false),samples};
    };
    const single=cases.map(row=>render(row,new THREE.Vector3(...row.point)));
    const anchor=new THREE.Vector3(...sequence.initial),ctx={_specAnchor:anchor,_specAnchorOk:true};
    const frames=sequence.steps.map(step=>{
      updateAnchor.call(ctx,locked,rules,lerp,sequence.view,new THREE.Vector3(...sequence.point),step.delta);
      const row={kind:'moving',character:sequence.character,point:sequence.point,yaw:sequence.yaw,pitch:sequence.pitch,
        view:sequence.view,hit:null,ridge:false};
      return {...render(row,anchor),deltaBits:bits(step.delta,true)};
    });
    return {capture:{cases:single,sequence:{...sequence,frames}},runtime:{userAgent:navigator.userAgent},cameraRules:rules};
  },{program,actors,cases,sequence}));
  runtime.browser=browser.version();
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during spectator TPS capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator TPS generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_tps.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,cameraRules,actors,...capture});
console.log('SPECTATOR_TPS_REFERENCES_PASS cases='+capture.cases.length+' movingFrames='+capture.sequence.frames.length);
