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
for(const path of ['public/js/game.js','public/js/data.js','tools/audit_src.mjs']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original PiP input changed: '+path);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const data=(await readFile(join(source,'public/js/data.js'),'utf8')).replace(/\r\n?/g,'\n');
const squad=/export const SQUAD = \{\s*N:\s*(\d+)/.exec(data);
if(!squad)throw new Error('Original squad count changed');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const selector=grabMethod(game,'_pipSources');
if(!game.includes('ent.si = e.si || 0;'))throw new Error('Original squad index publication changed');
const scenarios=[
  {name:'reversed',low:false,scale:1,rows:[{id:1,si:3},{id:2,si:1},{id:3,si:2}]},
  {name:'equal',low:false,scale:1,rows:[{id:7,si:2},{id:8,si:2},{id:9,si:2}]},
  {name:'low_power',low:true,scale:1,rows:[{id:11,si:4},{id:12,si:1}]},
  {name:'reduced_resolution',low:false,scale:.75,rows:[{id:31,si:3},{id:32,si:1}]},
  {name:'dead_first',low:false,scale:1,rows:[{id:21,si:1,dead:true},{id:22,si:3},{id:23,si:2}]},
  {name:'self_and_other_peer',low:false,scale:1,rows:[{id:41,si:0,isSelf:true},{id:42,si:0,pid:18},
    {id:43,si:3},{id:44,si:1}]},
  {name:'missing_indices',low:false,scale:1,rows:[{id:51},{id:52,si:0},{id:53,si:1}]},
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage();
  programs=await page.evaluate(({selector,scenarios})=>scenarios.map(sample=>{
    const Controller=new Function('lowPower','return class {'+selector+'}')( ()=>sample.low );
    const rows=sample.rows.map(row=>({pid:17,hero:true,isSelf:false,dead:false,decoy:false,lost:false,...row,
      si:row.si||0}));
    const client=Object.assign(new Controller(),{side:'STEEL',dead:false,isDrone:true,youId:17,
      _resScale:sample.scale,ents:new Map(rows.map(row=>[row.id,row]))});
    return {...sample,selected:client._pipSources().map(result=>result.ent.id)};
  }),{selector,scenarios});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original PiP input changed during capture: '+path);
const inputs={};
for(const path of ['tools/pip_squad_order_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/pip_squad_order.json'),
  {formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),defaultSquadCount:Number(squad[1]),programs});
console.log('PIP_SQUAD_ORDER_CAPTURE_PASS programs='+programs.length);
