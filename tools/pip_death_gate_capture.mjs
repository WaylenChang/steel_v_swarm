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
for(const path of ['public/js/game.js','tools/audit_src.mjs']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original death-view input changed: '+path);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(game,'_renderDeathCam');
const border=/const bw = ([\d.]+);/.exec(method);
const minimum=/if \(pw < ([\d.]+) \|\| ph < ([\d.]+)\) return;/.exec(method);
if(!border||!minimum||minimum[1]!==minimum[2])throw new Error('Missing original inset boundary rules');
const rules={border:Number(border[1]),minimum:Number(minimum[1])};
const basic={side:'STEEL',dead:true,canvas:{left:12.25,top:-3.5,width:640,height:360},
  frame:{left:33.5,top:18.25,width:200,height:100}};
const cases=[
  {name:'desktop'}, {name:'fractional',frame:{left:9.125,top:-1.375,width:101.5,height:56.25}},
  {name:'exact-minimum',frame:{left:1,top:2,width:10,height:10}},
  {name:'width-below',frame:{left:1,top:2,width:9.999999999999998,height:10}},
  {name:'height-below',frame:{left:1,top:2,width:10,height:9.999999999999998}},
  {name:'negative-position',canvas:{left:150.75,top:55.5,width:320,height:568},frame:{left:70.125,top:13.25,width:180,height:102}},
  {name:'alive',dead:false},{name:'transition',deathSeq:true},{name:'game-over',gameOver:true},
  {name:'missing-side',side:''},{name:'missing-config',missingConfig:true},
  {name:'missing-frame',missingFrame:true},{name:'hidden-frame',hidden:true}
].map(item=>({...basic,...item}));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage();
  programs=await page.evaluate(({cases,method})=>{
    const bits=value=>{const buffer=new ArrayBuffer(8);new DataView(buffer).setFloat64(0,value,true);
      return [...new Uint8Array(buffer)].map(byte=>byte.toString(16).padStart(2,'0')).join('');};
    return cases.map(item=>{
      const frame={offsetParent:item.hidden?null:{},getBoundingClientRect:()=>item.frame};
      const document={getElementById:()=>item.missingFrame?null:frame};
      const Client=new Function('document','THREE','llToWorld','return class {'+method+'}')(
        document,{Color:class{}},(x,z)=>[x,z]);
      let prepared=false,rendered=false,viewports=[];
      const camera={position:{set(){prepared=true;}},up:{set(){}},lookAt(){},updateProjectionMatrix(){}};
      const renderer={getClearColor:x=>x,getClearAlpha:()=>1,setScissorTest(){},setScissor(){},setClearColor(){},
        setViewport:(...value)=>viewports.push(value),render(){rendered=true;}};
      const client=Object.assign(new Client(),{side:item.side,dead:item.dead,_deathSeq:!!item.deathSeq,_gameOver:!!item.gameOver,
        cfg:item.missingConfig?null:{bases:{STEEL:[0,0],SWARM:[0,0]}},center:{},ents:new Map(),pipCam:camera,
        pos:{x:0,z:0},_surf:()=>0,renderer,scene:{},canvas:{clientWidth:item.canvas.width,clientHeight:item.canvas.height,
          getBoundingClientRect:()=>item.canvas}});
      client._renderDeathCam();
      return {...item,prepared,rendered,viewportBits:rendered?viewports[0].map(bits):[]};
    });
  },{cases,method});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original death-view input changed during capture: '+path);
const inputs={};
for(const path of ['tools/pip_death_gate_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
const base={formatVersion:1,source:{inputs,sourceInputs},rules};
await writeFixtureJson(join(root,'data/pip_death_gate.json'),base);
await writeFixtureJson(join(root,'tests/fixtures/pip_death_gate.json'),{...base,browser:browser.version(),programs});
console.log('PIP_DEATH_GATE_CAPTURE_PASS programs='+programs.length);
