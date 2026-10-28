import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/pip_window_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabConst,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const pip=/const PIP = (\{[^\n]+\});/.exec(game);
const side=/export const sideInfo = \(s\) =>\s*([^;]+);/.exec(data);
const touch=/const TOUCH_DPR_MAX = ([\d.]+);/.exec(game);
if(!pip||!side||!touch)throw new Error('Missing original PiP or pixel-ratio seams');
const program={pip:pip[1],sides:grabConst(data,'SIDES'),side:side[1],touch:Number(touch[1]),
  sources:grabMethod(game,'_pipSources'),render:grabMethod(game,'_renderPips'),dpr:grabMethod(game,'_dpr')};
const scenarios=[{size:[320,568],dpr:1},{size:[320,568],dpr:1.25},{size:[320,568],dpr:1.5},
  {size:[640,360],dpr:1},{size:[640,360],dpr:1.5},{size:[640,360],dpr:2},
  {size:[720,450],dpr:1},{size:[1440,900],dpr:1}];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const cases=[];let runtime;
try{
  for(const scenario of scenarios){
    const page=await browser.newPage({viewport:{width:scenario.size[0],height:scenario.size[1]},deviceScaleFactor:scenario.dpr});
    await page.route('**/*',async route=>{
      const url=new URL(route.request().url());
      if(url.origin!=='http://source.invalid')return route.abort();
      if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><body></body></html>'});
      if(url.pathname==='/three.module.js')return route.fulfill({contentType:'text/javascript',body:contents['out/forest_review/three.module.js']});
      return route.abort();
    });
    await page.goto('http://source.invalid/');
    const result=await page.evaluate(async({program,scenario})=>{
      document.head.innerHTML='<style>html,body{margin:0;overflow:hidden;background:#000}canvas{display:block}</style>';
      document.body.innerHTML='<canvas></canvas>';
      const THREE=await import('/three.module.js');
      const sides=new Function(program.sides+'\nreturn SIDES;')();
      const sideInfo=new Function('SIDES','THIRD','SUPER_SIDE','SUPER_INFO',
        'return (s)=>'+program.side+';')(sides,{SIDES:{}},'SUPER',{});
      const rules=new Function('return ('+program.pip+');')();
      const Pip=new Function('PIP','THREE','lowPower','sideInfo','isTouchUI','TOUCH_DPR_MAX',
        'return class {\n'+program.sources+'\n'+program.render+'\n'+program.dpr+'\n};')
        (rules,THREE,()=>false,sideInfo,()=>false,program.touch);
      const canvas=document.querySelector('canvas');
      canvas.style.width=scenario.size[0]+'px';canvas.style.height=scenario.size[1]+'px';
      const renderer=new THREE.WebGLRenderer({canvas,antialias:false,stencil:false,preserveDrawingBuffer:true});
      const gl=renderer.getContext(),boxes=[];
      const originalScissor=renderer.setScissor.bind(renderer);
      renderer.setScissor=(...args)=>{originalScissor(...args);boxes.push({logical:args,physical:Array.from(gl.getParameter(gl.SCISSOR_BOX))});};
      const mesh=new THREE.Object3D();
      const ent={pid:17,hero:false,isSelf:false,dead:false,decoy:true,lost:false,si:0,ry:0,mesh};
      const scene=new THREE.Scene();scene.background=new THREE.Color('#0000ff');
      const context=Object.assign(new Pip(),{side:'STEEL',dead:false,isDrone:false,youId:17,_resScale:1,
        ents:new Map([[7,ent]]),renderer,scene,canvas,cockpit:new THREE.Object3D(),
        pipCam:new THREE.PerspectiveCamera(rules.FOV,1/rules.ASPECT,.5,4000)});
      renderer.setPixelRatio(context._dpr());renderer.setSize(...scenario.size,false);
      renderer.setClearColor('#000000',1);renderer.clear(true,true,true);
      context._renderPips();
      if(boxes.length!==2||!renderer.capabilities.isWebGL2)throw new Error('Original PiP did not render one WebGL2 view');
      const border=boxes[0].physical;
      const pixels=new Uint8Array(canvas.width*canvas.height*4);
      gl.readPixels(0,0,canvas.width,canvas.height,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
      const sample=(border[1]*canvas.width+border[0])*4;
      const color=Array.from(pixels.slice(sample,sample+4));
      if(color[3]!==255||(color[0]===0&&color[1]===0))throw new Error('Original PiP border color is unavailable');
      let minX=canvas.width,minY=canvas.height,maxX=-1,maxY=-1;
      for(let offset=0;offset<pixels.length;offset+=4){
        if(pixels[offset]!==color[0]||pixels[offset+1]!==color[1]||pixels[offset+2]!==color[2]||pixels[offset+3]!==color[3])continue;
        const pixel=offset/4,x=pixel%canvas.width,y=Math.floor(pixel/canvas.width);
        minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);
      }
      const raster=[minX,canvas.height-maxY-1,maxX-minX+1,maxY-minY+1];
      const scissor=[border[0],canvas.height-border[1]-border[3],border[2],border[3]];
      if(JSON.stringify(raster)!==JSON.stringify(scissor))throw new Error('Original PiP border raster differs from its scissor');
      return {size:scenario.size,dpr:window.devicePixelRatio,pixelRatio:renderer.getPixelRatio(),
        client:[canvas.clientWidth,canvas.clientHeight],backing:[canvas.width,canvas.height],
        logicalBorder:boxes[0].logical,borderPixels:raster,scissorPixels:scissor,borderColor:color,
        restored:!renderer.getScissorTest()&&context.cockpit.visible&&mesh.visible,
        three:THREE.REVISION,userAgent:navigator.userAgent};
    },{program,scenario});
    await page.close();
    if(result.dpr!==scenario.dpr||result.pixelRatio!==scenario.dpr||!result.restored||
      result.client.some((value,index)=>value!==scenario.size[index])||
      result.backing.some((value,index)=>value!==scenario.size[index]*scenario.dpr))
      throw new Error('Original PiP window capture did not retain its requested scale: '+JSON.stringify(result));
    runtime??={browser:browser.version(),three:result.three,userAgent:result.userAgent,webgl:'webgl2'};
    delete result.three;delete result.userAgent;
    cases.push(result);
  }
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during PiP window capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('PiP window generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/pip_window.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},runtime,cases});
console.log('PIP_WINDOW_REFERENCES_PASS cases='+cases.length);
