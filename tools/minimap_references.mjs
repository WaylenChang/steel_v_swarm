import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {minimapMarkerReferences} from './minimap_marker_references.mjs';
import {minimapCadenceReferences} from './minimap_cadence_references.mjs';
import {minimapLaneReferences} from './minimap_lane_references.mjs';
import {minimapVisionReferences} from './minimap_vision_references.mjs';

export async function minimapCanvasSize(source) {
  const html=await readFile(join(source,'public/index.html'),'utf8');
  const canvas=/<canvas\s+id="minimap"\s+width="(\d+)"\s+height="(\d+)"/.exec(html);
  if(!canvas||Number(canvas[1])<=0||Number(canvas[2])<=0)throw new Error('Missing authored minimap canvas dimensions');
  return [Number(canvas[1]),Number(canvas[2])];
}

export async function minimapReferences(source,d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const text=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
  const declaration=/const MM_NEAR = (\{[\s\S]*?\n\});/.exec(text);
  if(!declaration)throw new Error('Missing original minimap vicinity constants');
  const rules=new Function('return ('+declaration[1]+');')();
  const methods=['_mmWindow','_world2mm','_world2mmFull','_toggleMmMode'].map(name=>grabMethod(text,name));
  const classes=[];
  const document={body:{classList:{toggle:(name,on)=>classes.push([name,on])}}};
  const Client=new Function('MM_NEAR','GAME','UNITS','document','return class {\n'+methods.join('\n')+'\n};')(rules,d.GAME,d.UNITS,document);
  const windows=[];
  const terrains=[{minX:-3000,maxX:4000,minZ:-2000,maxZ:2500},{minX:10,maxX:110,minZ:-60,maxZ:40},
    {minX:-50,maxX:50,minZ:-4000,maxZ:4000}];
  for(const terrain of terrains)for(const kind of [null,...Object.keys(d.UNITS)])for(const mode of ['full','near'])
  for(const position of [[0,0],[terrain.minX,terrain.minZ],[terrain.maxX,terrain.maxZ],[-10000,12000]]) {
    const client=new Client();Object.assign(client,{terrain,heroKind:kind,mmMode:mode,pos:{x:position[0],z:position[1]}});
    const window=client._mmWindow();
    const points=[position,[terrain.minX,terrain.minZ],[terrain.maxX,terrain.maxZ],[window.x0,window.z0],[window.x1,window.z1]];
    windows.push({terrain,kind,mode,position,window,points:points.map(point=>({point,
      current:client._world2mm(...point,250,220),full:client._world2mmFull(...point,250,220)}))});
  }
  const client=new Client(),notices={},toggles=[];
  Object.assign(client,{mmMode:'full',_mmLast:7,hud:{feed:message=>{notices[client.mmMode]=message;}}});
  for(let index=0;index<3;index++) {
    client._mmLast=7;client._toggleMmMode();
    toggles.push({mode:client.mmMode,last:client._mmLast,active:classes.at(-1)[1],message:notices[client.mmMode]});
  }
  const draw=grabMethod(text,'_drawMinimap');
  const markers=minimapMarkerReferences(text,draw,d);
  const cadence=minimapCadenceReferences(grabMethod(text,'_initMinimap'),draw);
  const lanes=minimapLaneReferences(grabMethod(text,'_gradeLanes'),draw,d);
  const vision=minimapVisionReferences(text,['_buildBlockGrid','_blockersNear','_mmVision','_mmShadows'].map(name=>grabMethod(text,name)),draw,d);
  return {rules:{...rules,canvas:await minimapCanvasSize(source),notices,markers:markers.rules,lanes:lanes.rules,fog:vision.rules,...cadence.rules},
    fixtures:{minimapWindows:windows,minimapToggles:toggles,...markers.fixtures,...cadence.fixtures,...lanes.fixtures,...vision.fixtures}};
}
