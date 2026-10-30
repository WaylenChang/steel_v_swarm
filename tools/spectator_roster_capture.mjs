import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original spectator input changed: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const methods=['_specRoster','_specName','_specFollow','_specSetView'].map(name=>grabMethod(contents['public/js/game.js'],name));
const literals=grabConst(contents['public/js/data.js'],'SPEC_CAM')+'\n'+grabConst(contents['public/js/data.js'],'SIDES');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let cases;
try{
  const page=await browser.newPage();
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.origin!=='http://source.invalid')return route.abort();
    if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html><body></body></html>'});
    if(url.pathname==='/three.mjs')return route.fulfill({contentType:'text/javascript',body:contents['out/forest_review/three.module.js']});
    return route.abort();
  });
  await page.goto('http://source.invalid/');
  cases=await page.evaluate(async ({methods,literals})=>{
    const THREE=await import('/three.mjs');
    const settings=new Function(literals+'\nreturn {SPEC_CAM,SIDES};')();
    const Client=new Function('SPEC_CAM','SIDES','CHARACTERS','return class {\n'+methods.join('\n')+'\n};')(
      settings.SPEC_CAM,settings.SIDES,{});
    const row=(tag,pid,side='STEEL',hero=true,act=true)=>({tag,pid,side,hero,act,position:[5,0,0]});
    const programs=[
      {name:'all_equal',rows:Array.from({length:24},(_,i)=>row('equal-'+i,'2'))},
      {name:'mixed_ties',rows:Array.from({length:36},(_,i)=>row('mixed-'+i,['b2','10','2'][i%3],i%4===0?'SWARM':'STEEL'))},
      {name:'filtered_ties',rows:Array.from({length:20},(_,i)=>row('filtered-'+i,'3','STEEL',i%5!==0,i%7!==0))},
      {name:'tie_and_nearest',rows:[row('first','8'),row('second','8'),row('third','8')]},
    ];
    return programs.map(program=>{
      const messages=[];
      const client=Object.assign(new Client(),{pos:new THREE.Vector3(),_specView:'god',_specPid:null,
        _specAnchorOk:true,pitch:-.9,ents:new Map(program.rows.map((entry,index)=>[index,{...entry,mesh:{position:new THREE.Vector3(...entry.position)}}])),
        hud:{feed:value=>messages.push(value)}});
      const ordered=client._specRoster();
      client._specFollow(0);
      return {...program,ordered:ordered.map(entry=>entry.tag),pid:client._specPid,
        target:client._specRoster().find(entry=>entry.pid===client._specPid)?.tag??null,messages};
    });
  },{methods,literals});
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original spectator input changed during capture: '+path);
const inputs={};
for(const path of ['tools/spectator_roster_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/spectator_roster.json'),{formatVersion:1,source:{inputs,sourceInputs},browser:browser.version(),cases});
console.log('SPECTATOR_ROSTER_CAPTURE_PASS cases='+cases.length);
