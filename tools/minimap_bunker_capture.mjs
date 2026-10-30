import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const paths=['public/js/game.js','public/js/data.js','tools/audit_src.mjs'],sourceInputs={};
for(const path of paths){const bytes=await readFile(join(source,path));sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original source changed: '+path);}
const game=(await readFile(join(source,paths[0]),'utf8')).replace(/\r\n?/g,'\n');
const {grabBlock,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const snap=grabMethod(game,'_applySnap');
const marker="if (e.k === 'bunker')";
const block=grabBlock(snap,marker);
if(!block.includes('this._seenBunkers.set')||!block.includes('Math.round')||!block.includes('const bz = -e.z'))
  throw new Error('Original bunker memory changed');
const draw=grabMethod(game,'_drawMinimap');
const projection=grabMethod(game,'_world2mm');
const fullProjection=grabMethod(game,'_world2mmFull');
const {sideInfo}=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const colors=Object.fromEntries(['STEEL','SWARM','GUER','MILI'].map(side=>[side,sideInfo(side).color]));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let frames;
try{
  const page=await browser.newPage();
  frames=await page.evaluate(({block,marker,draw,projection,fullProjection,colors})=>{
    const Client=new Function('sideInfo','laneCssColor',`return class { ${draw}\n${projection}\n${fullProjection} }`)
      (side=>({color:colors[side]}),()=> '#000');
    const remember=new Function('e',`${marker} ${block}`),ctx={_seenBunkers:new Map()};
    const f=Math.fround;
    const bunker=(x,z,s='STEEL')=>({k:'bunker',x:f(x),z:f(z),s});
    const snapshots=[
      [],
      [bunker(-.5,.5),bunker(.4999999701976776,-.4999999701976776,'SWARM'),bunker(.5,-.5)],
      [bunker(-.5000000596046448,.5000000596046448,'MILI'),bunker(18.5,-28.5,'GUER'),{k:'tower',x:19,z:-29,s:'STEEL'}],
      [],
      [bunker(.25,-.25,'MILI'),bunker(18.25,-28.25,'SWARM'),bunker(100.5,100.5)],
      [bunker(0,0,'STEEL'),bunker(-100.5,-100.5,'GUER')],
      []
    ];
    return snapshots.map((rows,index)=>{
      for(const row of rows)remember.call(ctx,row);
      const markers=[];
      const canvas={drawImage(){},setLineDash(){},fillRect(x,y,w,h){if(w===5&&h===5)markers.push({rect:[x,y,w,h],color:this.fillStyle});},
        strokeRect(){},measureText(){return {width:0}},fillText(){}};
      const client=Object.assign(new Client(),{side:'',_mmLast:0,_mmWarmUntil:0,
        terrain:{minX:-200,maxX:200,minZ:-200,maxZ:200},_mmWin:{x0:-200,x1:200,z0:-200,z1:200},
        _mmWindow(){return this._mmWin},_mmBase:{},_mmLanes:[],_seenBunkers:ctx._seenBunkers,
        ents:new Map(),samMeshes:new Map(),cfg:{},mmMode:'full',minimapCanvas:{width:220,height:220},mmCtx:canvas});
      client._drawMinimap(100+index);
      return {rows,records:[...ctx._seenBunkers].map(([key,value])=>({key,...value})),markers};
    });
  },{block,marker,draw,projection,fullProjection,colors});
}finally{await browser.close();}
for(const path of paths)if(digest(await readFile(join(source,path)))!==sourceInputs[path])throw new Error('Source changed during capture: '+path);
const inputs={};for(const path of ['tools/minimap_bunker_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/minimap_bunker.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),frames});
console.log('MINIMAP_BUNKER_CAPTURE_PASS frames='+frames.length);
