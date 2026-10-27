import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/minimap_frame_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={},files={};
// Only these extracted methods and literals are evaluated; the data module is not imported.
for(const path of ['public/js/game.js','public/js/data.js','public/index.html','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
  files[path]=bytes.toString('utf8').replace(/\r\n?/g,'\n');
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=files['public/js/game.js'],data=files['public/js/data.js'],html=files['public/index.html'];
const near=/const MM_NEAR = (\{[\s\S]*?\n\});/.exec(game);
const gameRules=/export const GAME = \{([\s\S]*?)\n\};/.exec(data);
const sight=gameRules&&/\bAIM_SIGHT_MULT:\s*([\d.]+)/.exec(gameRules[1]);
const canvas=/<canvas\s+id="minimap"\s+width="(\d+)"\s+height="(\d+)"/.exec(html);
if(!near||!sight||!canvas)throw new Error('Missing original minimap constants or canvas');
const methods=['_mmWindow','_world2mm','_world2mmFull','_toggleMmMode','_drawMinimap'].map(name=>grabMethod(game,name));
const rules=new Function('return ('+near[1]+');')();
const document={body:{classList:{toggle(){}}}};
const Client=new Function('MM_NEAR','GAME','UNITS','document','sideInfo','laneCssColor',
  'return class {\n'+methods.join('\n')+'\n};')(rules,{AIM_SIGHT_MULT:Number(sight[1])},{},document,
    ()=>({color:'#test-marker'}),()=> '#test-lane');
const ctx={frame:null,path:[],fillStyle:'',strokeStyle:'',
  drawImage(_image,x,y,w,h){this.frame={crop:[x,y,w,h],lanes:[],markers:[],bunkers:[],missiles:[],missileColour:null,arrow:null,label:null,labelColour:null};},
  setLineDash(){},beginPath(){this.path=[];},moveTo(x,y){this.path.push([x,y]);},
  lineTo(x,y){this.path.push([x,y]);},stroke(){this.frame.lanes.push(this.path);},
  fillRect(x,y,w,h){if(this.fillStyle==='#test-marker'&&w===6)this.frame.markers.push([x+w/2,y+h/2]);
    if(this.fillStyle==='#test-marker'&&w===5)this.frame.bunkers.push([x+w/2,y+h/2]);
    if(w===3&&h===3){this.frame.missiles.push([x+w/2,y+h/2]);this.frame.missileColour=this.fillStyle;}},
  strokeRect(){},
  save(){this.transform={point:[0,0],rotation:0};},translate(x,y){this.transform.point=[x,y];},
  rotate(angle){this.transform.rotation=angle;},closePath(){},fill(){this.frame.arrow=this.transform;},restore(){this.transform=null;},
  measureText(){return {width:0};},fillText(text){this.frame.label=text;this.frame.labelColour=this.fillStyle;}};
const terrain={minX:-2000,maxX:2000,minZ:-1500,maxZ:1500};
const entity={kind:'tower',side:'STEEL',neutral:false,mesh:{position:{x:900,z:300}}};
const client=Object.assign(new Client(),{terrain,pos:{x:800,z:500},heroKind:'',mmMode:'full',side:'',
  _mmLast:0,_mmWarmUntil:0,_mmBase:{},_mmLanes:[[{x:0,z:0,grade:'ground'},{x:800,z:0,grade:'ground'}]],
  _seenBunkers:new Map([['400,300',{x:400,z:300,side:'STEEL'}]]),ents:new Map([[7,entity]]),samMeshes:new Map(),cfg:{laneIds:[0]},
  minimapCanvas:{width:Number(canvas[1]),height:Number(canvas[2])},mmCtx:ctx});
const cases=[];
const snapshot=(target,name,due)=>target.push({name,due,last:client._mmLast,window:{...client._mmWin},...structuredClone(ctx.frame)});
client._drawMinimap(100); snapshot(cases,'initial',true);
client._toggleMmMode();
client.pos={x:1000,z:600}; entity.mesh.position={x:1000,z:0};
client._seenBunkers.get('400,300').x=-400; client._seenBunkers.get('400,300').z=-300;
snapshot(cases,'pending-toggle',false);
client._drawMinimap(100.1); snapshot(cases,'near',true);
client.pos={x:-1000,z:-600}; entity.mesh.position={x:-900,z:-300};
client._drawMinimap(100.15); snapshot(cases,'gated-movement',false);
client._drawMinimap(100.35); snapshot(cases,'near-moved',true);
const factionCases=[];
Object.assign(client,{side:'STEEL',mmMode:'full',_mmLast:0,_pulseUntil:1000,pos:{x:800,z:500},
  viewMode:'tps',yaw:.73,bodyYaw:-1.2,_mmVision:()=>[],
  _mmSeen:{getContext:()=>({fillRect(){}})},_mmScr:{getContext:()=>({})},
  _seenBunkers:new Map([['400,300',{x:400,z:300,side:'STEEL'}]]),
  samMeshes:new Map([[1,{mesh:{position:{x:-1000,z:300}}}]])});
entity.mesh.position={x:900,z:300};
client._drawMinimap(200); snapshot(factionCases,'faction-initial',true);
client._toggleMmMode();
Object.assign(client,{side:'SWARM',pos:{x:1000,z:600},bodyYaw:.4});
entity.mesh.position={x:1000,z:0};
client._seenBunkers.get('400,300').x=-400; client._seenBunkers.get('400,300').z=-300;
client.samMeshes.get(1).mesh.position={x:1300,z:600};
snapshot(factionCases,'faction-pending',false);
client._drawMinimap(200.1); snapshot(factionCases,'faction-near',true);
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during minimap frame capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Minimap frame generator changed during capture');
await writeFixtureJson(join(root,'tests/fixtures/minimap_frame.json'),{formatVersion:1,
  source:{inputs:{[generator]:generatorHash},sourceInputs},canvas:[Number(canvas[1]),Number(canvas[2])],terrain,cases,factionCases});
console.log('MINIMAP_FRAME_REFERENCES_PASS cases='+cases.length+' faction='+factionCases.length);
