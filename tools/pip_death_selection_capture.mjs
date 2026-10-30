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
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original death-view input changed: '+path);
}
const game=await readFile(join(source,'public/js/game.js'),'utf8');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(game.replace(/\r\n?/g,'\n'),'_renderDeathCam');
const tower=(id,side,x,z,extra={})=>({id,kind:'tower',side,position:[x,0,z],...extra});
const base=(id,side,x,z,extra={})=>({id,kind:'base',side,position:[x,0,z],...extra});
const cases=[
  {name:'nearest-tower',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',50,0),tower(2,'STEEL',10,0),tower(3,'SWARM',1,0),base(4,'STEEL',0,0)]},
  {name:'later-tie',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',-10,0),tower(2,'STEEL',10,0)]},
  {name:'first-tie',side:'SWARM',enemy:[0,0],rows:[tower(1,'SWARM',0,10),tower(2,'SWARM',0,-10)]},
  {name:'dead-and-no-mesh',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',0,0,{dead:true}),tower(2,'STEEL',1,0,{mesh:false}),tower(3,'STEEL',20,0)]},
  {name:'first-base-even-dead',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0,{dead:true}),base(2,'STEEL',300,0,{dead:true}),base(3,'STEEL',1,0)]},
  {name:'base-with-mesh',side:'SWARM',enemy:[0,0],rows:[base(1,'SWARM',0,0,{mesh:false}),base(2,'STEEL',0,0),base(3,'SWARM',10,0)]},
  {name:'fallback',side:'STEEL',enemy:[0,0],rows:[tower(1,'SWARM',1,0),base(2,'SWARM',0,0)]},
  {name:'precision-near-tie',side:'STEEL',enemy:[2477.912841796875,133.73895263671875],rows:[tower(1,'STEEL',2561.746337890625,80.00074768066406),tower(2,'STEEL',2561.746337890625,80.0007553100586)]},
  {name:'hidden-source',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0,{visible:false}),tower(2,'STEEL',10,0)]},
  {name:'nonfinite-then-finite',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL','NaN',0),tower(2,'STEEL','Infinity',0),tower(3,'STEEL',12,0)]},
  {name:'nonfinite-base-fallback',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL','Infinity',0),tower(2,'STEEL','NaN',0),base(3,'STEEL',4,0)]},
  {name:'missing-side',side:'',enemy:[0,0],rows:[tower(1,'STEEL',1,0)]},
  {name:'alive',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],dead:false},
  {name:'transition',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],deathSeq:true},
  {name:'game-over',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],gameOver:true},
  {name:'missing-config',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],missingConfig:true},
  {name:'missing-frame',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],missingFrame:true},
  {name:'hidden-frame',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],hidden:true},
  {name:'small-frame',side:'STEEL',enemy:[0,0],rows:[tower(1,'STEEL',1,0)],small:true},
];
for(const item of cases)for(const value of [...item.enemy,...item.rows.flatMap(row=>row.position)])
  if(typeof value==='number'&&!Object.is(value,Math.fround(value)))throw new Error('Fixture coordinates must survive native vector storage');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage();
  programs=await page.evaluate(({cases,method})=>cases.map(item=>{
    const frame={offsetParent:item.hidden?null:{},getBoundingClientRect:()=>({left:10,top:10,width:item.small?8:200,height:100})};
    const document={getElementById:()=>item.missingFrame?null:frame};
    const THREE={Color:class{}};
    const Client=new Function('document','THREE','llToWorld','return class {'+method+'}')(document,THREE,(x,z)=>[x,z]);
    let selectedForDraw=null;
    const entities=item.rows.map(row=>{
      let visible=row.visible??true;
      const value=n=>n==='NaN'?NaN:n==='Infinity'?Infinity:n;
      const mesh=row.mesh===false?null:{position:{x:value(row.position[0]),y:value(row.position[1]),z:value(row.position[2])},
        get visible(){return visible;},set visible(value){visible=value;if(!value)selectedForDraw=row.id;}};
      return {...row,mesh};
    });
    const camera={position:{set(){}},up:{set(){}},lookAt(){},updateProjectionMatrix(){}};
    let rendered=false,selected=null;
    const renderer={getClearColor:x=>x,getClearAlpha:()=>1,setScissorTest(){},setViewport(){},setScissor(){},setClearColor(){},
      render(){rendered=true;selected=selectedForDraw;}};
    const client=Object.assign(new Client(),{side:item.side,dead:item.dead??true,_deathSeq:!!item.deathSeq,_gameOver:!!item.gameOver,
      cfg:item.missingConfig?null:{bases:{STEEL:item.enemy,SWARM:item.enemy}},center:{},ents:new Map(entities.map(row=>[row.id,row])),pipCam:camera,
      pos:{x:0,z:0},_surf:()=>0,renderer,scene:{},canvas:{clientWidth:640,clientHeight:360,getBoundingClientRect:()=>({left:0,top:0})},cockpit:{visible:true}});
    client._renderDeathCam();
    return {...item,rendered,selected,restored:client.cockpit.visible&&entities.every(row=>!row.mesh||row.mesh.visible===(row.visible??true))};
  }),{cases,method});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original death-view input changed during capture: '+path);
const inputs={};
for(const path of ['tools/pip_death_selection_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/pip_death_selection.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),programs});
console.log('PIP_DEATH_SELECTION_CAPTURE_PASS programs='+programs.length);
