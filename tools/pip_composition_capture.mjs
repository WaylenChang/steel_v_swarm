import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/pip_composition_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
// These extracted methods use only the original literals below, not the data module's RNG imports.
const files=['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs'];
const sourceInputs={},contents={};
for(const file of files){
  const bytes=await readFile(join(source,file));
  sourceInputs[file]=digest(bytes);
  if(provenance.inputs?.[file]!==sourceInputs[file])throw new Error('Refresh shared source metadata first: '+file);
  contents[file]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const pip=/const PIP = (\{[^\n]+\});/.exec(game);
const side=/export const sideInfo = \(s\) =>\s*([^;]+);/.exec(data);
if(!pip||!side)throw new Error('Missing original PiP rules or sideInfo expression');
const program={pip:pip[1],sides:grabConst(data,'SIDES'),side:side[1],
  sources:grabMethod(game,'_pipSources'),render:grabMethod(game,'_renderPips')};
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const cases=[];let runtime,poseCases;
try{
  const page=await browser.newPage({viewport:{width:320,height:568},deviceScaleFactor:1});
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.origin!=='http://source.invalid')return route.abort();
    if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><body></body></html>'});
    if(url.pathname==='/three.module.js')return route.fulfill({contentType:'text/javascript',body:contents['out/forest_review/three.module.js']});
    return route.abort();
  });
  await page.goto('http://source.invalid/');
  runtime=await page.evaluate(async program=>{
    document.head.innerHTML='<style>html,body{margin:0;overflow:hidden;background:#000}canvas{display:block}#hud{position:absolute;left:20px;top:65px;width:8px;height:8px;background:#f00}</style>';
    document.body.innerHTML='<canvas></canvas><div id="hud"></div>';
    const THREE=await import('/three.module.js');
    const sides=new Function(program.sides+'\nreturn SIDES;')();
    const sideInfo=new Function('SIDES','THIRD','SUPER_SIDE','SUPER_INFO',
      'return (s) => '+program.side+';')(sides,{SIDES:{}},'SUPER',{});
    const rules=new Function('return ('+program.pip+');')();
    const power={low:false};
    const Pip=new Function('PIP','THREE','lowPower','sideInfo',
      'return class {\n'+program.sources+'\n'+program.render+'\n};')(rules,THREE,()=>power.low,sideInfo);
    const canvas=document.querySelector('canvas');
    const renderer=new THREE.WebGLRenderer({canvas,antialias:false,stencil:false,preserveDrawingBuffer:true});
    renderer.setPixelRatio(1);
    const scene=new THREE.Scene();
    const context=Object.assign(new Pip(),{side:'STEEL',dead:false,isDrone:false,youId:17,_resScale:1,
      ents:new Map(),renderer,scene,canvas,cockpit:new THREE.Object3D(),
      pipCam:new THREE.PerspectiveCamera(rules.FOV,1/rules.ASPECT,.5,4000)});
    for(const row of [{id:7,dead:false},{id:9,dead:true}]){
      const mesh=new THREE.Object3D();
      context.ents.set(row.id,{...row,pid:17,hero:false,isSelf:false,decoy:true,lost:false,si:0,ry:0,mesh});
    }
    window.pipCapture={THREE,power,context};
    const gl=renderer.getContext(),debug=gl.getExtension('WEBGL_debug_renderer_info');
    return {three:THREE.REVISION,webgl:renderer.capabilities.isWebGL2?'webgl2':'webgl',color:sideInfo('STEEL').color,
      renderer:debug?gl.getParameter(debug.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER),deviceScaleFactor:window.devicePixelRatio};
  },program);
  runtime.browser=browser.version();
  if(runtime.webgl!=='webgl2'||runtime.deviceScaleFactor!==1)
    throw new Error('PiP composition capture requires WebGL2 at device scale 1');
  for(const [width,height,modes] of [[320,568,['full','low']],[1440,900,['full','low']],
    [3840,2160,['full','low']],[320,568,['hidden_source','power']]]){
    await page.setViewportSize({width,height});
    for(const mode of modes){
      const state=await page.evaluate(({width,height,mode})=>{
        const {THREE,power,context}=window.pipCapture;
        power.low=mode==='power';context._resScale=mode==='low' ? .5 : 1;
        context.cockpit.visible=mode!=='hidden_source';
        context.ents.get(7).mesh.visible=mode!=='hidden_source';
        context.ents.get(9).mesh.visible=true;
        context.canvas.style.width=width+'px';context.canvas.style.height=height+'px';
        context.renderer.setSize(width,height,false);
        context.renderer.setClearColor('#000000',1);context.renderer.setScissorTest(false);
        context.renderer.setViewport(0,0,width,height);context.renderer.clear(true,true,true);
        context.scene.background=new THREE.Color(mode==='low'||mode==='power'?'#00ff00':'#0000ff');
        const selected=context._pipSources().map(row=>row.ent.id);
        context._renderPips();
        return {selected,cockpit:context.cockpit.visible,scissor:context.renderer.getScissorTest(),
          viewport:context.renderer.getViewport(new THREE.Vector4()).toArray(),
          clear:context.renderer.getClearColor(new THREE.Color()).getHexString(),alpha:context.renderer.getClearAlpha(),
          client:[context.canvas.clientWidth,context.canvas.clientHeight],
          backing:[context.canvas.width,context.canvas.height],
          sourceVisibility:[...context.ents.values()].map(row=>({id:row.id,visible:row.mesh.visible}))};
      },{width,height,mode});
      const png=await page.screenshot({type:'png'});
      const expected=mode==='low'||mode==='power'?[7]:[7,9];
      const hidden=mode==='hidden_source';
      if(JSON.stringify(state.selected)!==JSON.stringify(expected)||state.cockpit===hidden||state.scissor||
        JSON.stringify(state.viewport)!==JSON.stringify([0,0,width,height])||state.clear!=='000000'||state.alpha!==1||
        JSON.stringify(state.client)!==JSON.stringify([width,height])||JSON.stringify(state.backing)!==JSON.stringify([width,height])||
        JSON.stringify(state.sourceVisibility)!==JSON.stringify([{id:7,visible:!hidden},{id:9,visible:true}]))
        throw new Error('Original PiP renderer did not restore its state: '+JSON.stringify({width,height,mode,state}));
      if(png.length<24||png.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||
        png.readUInt32BE(16)!==width||png.readUInt32BE(20)!==height)
        throw new Error('Original PiP screenshot has invalid PNG dimensions');
      cases.push({size:[width,height],mode,...state,png:png.toString('base64'),sha256:digest(png)});
    }
  }
  poseCases=await page.evaluate(()=>{
    const {THREE,power,context}=window.pipCapture;
    const bits=(value,wide)=>{
      const buffer=new ArrayBuffer(wide?8:4),view=new DataView(buffer);
      if(wide)view.setFloat64(0,value,true);else view.setFloat32(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
    };
    const values=[-200/37,-146/37,-81/37,-.5,0,2/37,3/37,6/37,13/37,18/37,1/3,1,1000];
    const angles=[0,.73,-2.35,Math.PI,-Math.PI,20000.12,20000.13,-20000.12,
      1000000.01,1000000.02,Math.PI/2,-Math.PI/2,1e-8];
    const cases=[];
    for(const decoy of [true,false])for(let index=0;index<values.length;index++){
      const size=index%2?[320,568]:[1440,900],yaw=angles[index];
      const position=[Math.fround(123.4567),Math.fround(values[index]),Math.fround(-987.6543)];
      const mesh=new THREE.Object3D();mesh.position.fromArray(position);
      const entity={id:7,pid:17,hero:!decoy,isSelf:false,dead:false,decoy,lost:false,si:0,ry:yaw,mesh};
      let viewport=[],draws=[],scissor=false;
      const renderer={getClearColor:target=>target.setHex(0x123456),getClearAlpha:()=>.4,
        setClearColor:()=>{},setScissorTest:value=>{scissor=value;},setScissor:()=>{},clear:()=>{},
        setViewport:(...value)=>{viewport=value;},render:(_scene,camera)=>{
          camera.updateMatrixWorld(true);
          const cameraPosition=camera.position.toArray();
          const columns=[0,1,2,4,5,6,8,9,10];
          const matrix=camera.matrixWorld.elements,basis=columns.map(i=>matrix[i]);
          const inverse=camera.matrixWorldInverse.elements,inverseBasis=columns.map(i=>inverse[i]);
          const inversePosition=[12,13,14].map(i=>inverse[i]);
          const quaternion=camera.quaternion.toArray();
          draws.push({rect:[viewport[0],size[1]-viewport[1]-viewport[3],viewport[2],viewport[3]],
            position:cameraPosition,positionBits:cameraPosition.map(value=>bits(value,true)),
            positionFloat32:cameraPosition.map(Math.fround),positionFloat32Bits:cameraPosition.map(value=>bits(value,false)),
            quaternion,quaternionBits:quaternion.map(value=>bits(value,true)),
            basis,basisFloat32Bits:basis.map(value=>bits(value,false)),
            inverseBasis,inverseBasisFloat32Bits:inverseBasis.map(value=>bits(value,false)),
            inversePosition,inversePositionFloat32Bits:inversePosition.map(value=>bits(value,false)),
            yaw:camera.rotation.y,fov:camera.fov,aspect:camera.aspect});}};
      Object.assign(context,{side:'STEEL',dead:false,isDrone:!decoy,youId:17,_resScale:1,
        ents:new Map([[entity.id,entity]]),renderer,scene:{},canvas:{clientWidth:size[0],clientHeight:size[1]},cockpit:new THREE.Object3D()});
      power.low=false;
      context._renderPips();
      if(draws.length!==1||scissor||!context.cockpit.visible||!mesh.visible||
        JSON.stringify(viewport)!==JSON.stringify([0,0,...size]))
        throw new Error('Original PiP pose render did not restore its state');
      cases.push({decoy,size,position,yaw,yawBits:bits(yaw,true),draw:draws[0]});
    }
    return cases;
  });
}finally{await browser.close();}
for(const [file,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during PiP composition capture: '+file);
const inputs={};
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('PiP composition generator changed during capture');
inputs[generator]=generatorHash;
await writeFixtureJson(join(root,'tests/fixtures/pip_composition.json'),
  {formatVersion:1,source:{inputs,sourceInputs},runtime,cases,poseCases});
console.log('PIP_COMPOSITION_REFERENCES_PASS cases='+cases.length+' poses='+poseCases.length+' three='+runtime.three+' '+runtime.webgl);
