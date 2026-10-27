import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/spectator_nearest_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},contents={};
// Only the extracted spectator methods and literals are evaluated; data.js is not imported.
for(const path of ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  contents[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const game=contents['public/js/game.js'],data=contents['public/js/data.js'];
const literals=new Function(grabConst(data,'SPEC_CAM')+'\n'+grabConst(data,'SIDES')+'\nreturn {SPEC_CAM,SIDES};')();
const methods=['_specRoster','_specName','_specFollow','_specSetView'].map(name=>grabMethod(game,name));
const Client=new Function('SPEC_CAM','SIDES','CHARACTERS','return class {\n'+methods.join('\n')+'\n};')(
  literals.SPEC_CAM,literals.SIDES,{});
const small=2**-17,large=2**-14,shift=2**-16;
const pairs=[
  {name:'xy-near-tie',camera:[0,0,0],first:[100+small,100-small,0],second:[100,100,0]},
  {name:'xz-near-tie',camera:[0,0,0],first:[100+small,0,100-small],second:[100,0,100]},
  {name:'yz-near-tie',camera:[0,0,0],first:[0,100+small,100-small],second:[0,100,100]},
  {name:'three-axis-near-tie',camera:[0,0,0],first:[100+small,100-small,100],second:[100,100,100]},
  {name:'negative-near-tie',camera:[0,0,0],first:[-100-small,-100+small,0],second:[-100,-100,0]},
  {name:'shifted-near-tie',camera:[128,128,128],first:[228+shift,228-shift,128],second:[228,228,128]},
  {name:'map-scale-near-tie',camera:[0,0,0],first:[1000+large,1000-large,0],second:[1000,1000,0]},
  {name:'stable-exact-tie',camera:[0,0,0],first:[100,100,0],second:[-100,-100,0]},
  {name:'first-is-nearest',camera:[0,0,0],first:[100,100,0],second:[100+small,100-small,0]}
];
const bits=value=>{const data=Buffer.alloc(8);data.writeDoubleLE(value);return data.toString('hex');};
const cases=[];
for(const pair of pairs)for(const action of ['follow','mode']){
  for(const point of [pair.camera,pair.first,pair.second])
    if(!point.every(value=>Object.is(value,Math.fround(value))))throw new Error('Input must be exactly representable by native Vector3');
  const rows=[{pid:'2',side:'STEEL',position:pair.second,hero:true,act:true},
    {pid:'9',side:'STEEL',position:pair.camera,hero:false,act:true},
    {pid:'8',side:'STEEL',position:pair.camera,hero:true,act:false},
    {pid:'1',side:'STEEL',position:pair.first,hero:true,act:true}];
  const messages=[];
  const client=Object.assign(new Client(),{pos:new THREE.Vector3(...pair.camera),_specView:'god',_specPid:null,
    _specAnchorOk:true,pitch:-.9,ents:new Map(rows.map((row,index)=>[index,{...row,mesh:{position:new THREE.Vector3(...row.position)}}])),
    hud:{feed:value=>messages.push(value)}});
  const roster=client._specRoster();
  const distances=roster.map(row=>({pid:row.pid,value:client.pos.distanceToSquared(row.mesh.position),
    bits:bits(client.pos.distanceToSquared(row.mesh.position))}));
  if(action==='follow')client._specFollow(0);else client._specSetView('fpv');
  cases.push({name:pair.name,action,camera:pair.camera,rows,distances,
    result:{pid:client._specPid,mode:client._specView,pitch:client.pitch,anchorOk:client._specAnchorOk,
      roster:roster.map(row=>row.pid),messages}});
}
const groups=[
  {name:'nearest-not-last',rows:[{pid:'3',side:'STEEL',position:[30,0,0]},
    {pid:'1',side:'STEEL',position:[100,0,0]},{pid:'2',side:'STEEL',position:[20,0,0]}]},
  {name:'later-exact-tie',rows:[{pid:'3',side:'STEEL',position:[-20,0,0]},
    {pid:'1',side:'STEEL',position:[100,0,0]},{pid:'2',side:'STEEL',position:[20,0,0]}]},
  {name:'side-and-bot-order',rows:[{pid:'2',side:'SWARM',position:[20,0,0]},
    {pid:'b2',side:'STEEL',position:[200,0,0]},{pid:'10',side:'STEEL',position:[-20,0,0]}]}
];
const groupCases=[];
for(const group of groups)for(const action of ['follow','mode']){
  const rows=group.rows.map(row=>({...row,hero:true,act:true})),messages=[];
  const client=Object.assign(new Client(),{pos:new THREE.Vector3(),_specView:'god',_specPid:null,
    _specAnchorOk:true,pitch:-.9,ents:new Map(rows.map((row,index)=>[index,{...row,
      mesh:{position:new THREE.Vector3(...row.position)}}])),hud:{feed:value=>messages.push(value)}});
  const roster=client._specRoster();
  const distances=roster.map(row=>({pid:row.pid,value:client.pos.distanceToSquared(row.mesh.position),
    bits:bits(client.pos.distanceToSquared(row.mesh.position))}));
  if(action==='follow')client._specFollow(0);else client._specSetView('fpv');
  groupCases.push({name:group.name,action,camera:[0,0,0],rows,distances,
    result:{pid:client._specPid,mode:client._specView,pitch:client.pitch,anchorOk:client._specAnchorOk,
      roster:roster.map(row=>row.pid),messages}});
}
const special=value=>value==='NaN'?NaN:value==='Infinity'?Infinity:value;
const edgePairs=[
  {name:'nan-first',first:['NaN',0,0],second:[10,0,0]},
  {name:'nan-second',first:[10,0,0],second:['NaN',0,0]},
  {name:'infinity-first',first:['Infinity',0,0],second:[10,0,0]},
  {name:'infinity-second',first:[10,0,0],second:['Infinity',0,0]},
  {name:'equal-infinities',first:['Infinity',0,0],second:['Infinity',1,0]}
];
const edgeCases=[];
for(const pair of edgePairs){
  const rows=[{pid:'1',side:'STEEL',position:pair.first,hero:true,act:true},
    {pid:'2',side:'STEEL',position:pair.second,hero:true,act:true}];
  const client=Object.assign(new Client(),{pos:new THREE.Vector3(),_specView:'god',_specPid:null,
    _specAnchorOk:true,pitch:-.9,ents:new Map(rows.map((row,index)=>[index,{...row,
      mesh:{position:new THREE.Vector3(...row.position.map(special))}}])),hud:{feed(){}}});
  const distances=client._specRoster().map(row=>{
    const value=client.pos.distanceToSquared(row.mesh.position);
    return {pid:row.pid,kind:Number.isNaN(value)?'nan':Number.isFinite(value)?'finite':'infinity'};
  });
  client._specFollow(0);
  edgeCases.push({name:pair.name,rows,distances,pid:client._specPid});
}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during spectator nearest capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Spectator nearest generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/spectator_nearest.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},cameraRules:literals.SPEC_CAM,cases,groupCases,edgeCases});
console.log('SPECTATOR_NEAREST_REFERENCES_PASS cases='+cases.length+' groups='+groupCases.length+' edge='+edgeCases.length);
