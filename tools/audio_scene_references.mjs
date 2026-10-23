import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function audioSceneReferences(source,d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const text=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
  const names=['_moveCat','_entWeights','_updateMoveAudio','_updatePlaceAudio','_ambDensityAt'];
  const methods=Object.fromEntries(names.map(name=>[name,grabMethod(text,name)]));
  const scalar=(body,pattern)=>{const match=pattern.exec(body);if(!match)throw new Error('Missing original audio scene seam: '+pattern);return Number(match[1]);};
  const move=methods._updateMoveAudio,density=methods._ambDensityAt;
  const categories=/for \(const cat of (\[[^\n]+\])\)/.exec(move);
  if(!categories)throw new Error('Missing original movement audio categories');
  const rules={categories:new Function('return '+categories[1])(),maxDistance:scalar(move,/MAXD = ([\d.]+)/),
    referenceDistance:scalar(move,/REF = ([\d.]+)/),rateSlope:scalar(move,/RATE_K = ([\d.]+)/),
    densityBase:scalar(move,/dens = cl\(([\d.]+)/),densityStep:scalar(move,/cnt\[cat\] \* ([\d.]+)/),
    groundFloor:scalar(move,/const floor =[^\n]+\? ([\d.]+)/),airFloor:scalar(move,/const floor =[^\n]+: ([\d.]+)/),
    rateBase:scalar(move,/rate = cl\(([\d.]+)/),rateMinimum:scalar(move,/rate = cl\([^\n]+RATE_K, ([\d.]+)/),
    rateMaximum:scalar(move,/rate = cl\([^\n]+RATE_K, [\d.]+, ([\d.]+)/),
    urbanFull:scalar(density,/URB_FULL = ([\d.]+)/),forestFull:scalar(density,/FOR_FULL = ([\d.]+)/),
    cell:scalar(grabMethod(text,'_buildBlockGrid'),/const C = ([\d.]+)/),airThreshold:scalar(methods._moveCat,/\.air \|\| 0\) > ([\d.]+)/)};
  const create=(selfBed=false,queries=[])=>{
    const Scene=new Function('CHARACTERS','SELF_BED','terrainEnvCode','return class {\n'+Object.values(methods).join('\n')+'\n};')(
      d.CHARACTERS,selfBed,(_terrain,x,z)=>{queries.push([x,z]);return x>=0&&z<=0?1:2;});
    return new Scene();
  };
  const entity=(kind,position,extra={})=>({kind,mesh:{visible:true,position:{x:position[0],y:position[1],z:position[2]}},...extra});
  const hero=Object.keys(d.CHARACTERS)[0],categoriesCases=[];
  for(const kind of ['heli','tank','drone','soldier','robot','civilian'])for(const civ of [false,true]){
    const ent=entity(kind,[0,0,0],{civ});categoriesCases.push({entity:ent,result:create()._moveCat(ent)});
  }
  for(const ch of Object.keys(d.CHARACTERS))for(const flies of [false,true])for(const air of [0,.5,.500001,1]){
    const ent=entity('robot',[0,0,0],{hero:true,ch,flies,loco:{w:{air}}});categoriesCases.push({entity:ent,result:create()._moveCat(ent)});
  }
  const entities=[entity('heli',[20,10,0],{loco:{w:{walk:.2,run:.7}}}),entity('heli',[-20,10,0],{loco:null}),
    entity('heli',[200,0,0]),entity('heli',[200.001,0,0]),entity('tank',[30,0,-5],{loco:{w:{walk:1,run:0}}}),
    entity('drone',[0,5,-20],{loco:{w:{walk:0,run:1}}}),entity('robot',[8,0,-10],{hero:true,ch:hero,loco:{w:{walk:.3,run:.2,air:0}}}),
    entity('tank',[999,999,999],{isSelf:true}),entity('heli',[0,0,0],{isSelf:true}),
    entity('tank',[0,0,0],{dead:true}),entity('tank',[0,0,0],{isStatic:true}),entity('tank',[0,0,0],{mesh:{visible:false,position:{x:0,y:0,z:0}}})];
  const movement=[];
  for(const selfBed of [false,true])for(const low of [false,true])for(const ownWeights of [null,{walk:.1,run:.9,air:0}])for(const camera of [{position:[0,0,0],right:[1,0,0]},{position:[3,20,-5],right:[0,0,-1]}]){
    const queries=[],scene=create(selfBed,queries),calls=[];
    Object.assign(scene,{audio:{_dead:false,lowPower:low,setMove:(category,gain,pan,rate,wet)=>calls.push({category,gain,pan,rate,wet})},
      camera:{position:Object.fromEntries(['x','y','z'].map((axis,i)=>[axis,camera.position[i]])),matrixWorld:{elements:[camera.right[0],0,camera.right[2]]}},
      terrain:{},ents:new Map(entities.map((ent,i)=>[i,ent])),_selfW:ownWeights,_env:{ground:1},_updatePlaceAudio(){}});
    scene._updateMoveAudio();movement.push({selfBed,low,ownWeights,camera,entities,result:calls,queries});
  }
  const cells=[{cell:[-1,0],rows:[...Array.from({length:30},()=>({bld:true,cl:'tree'})),{cl:'tree'}]},
    {cell:[0,0],rows:Array.from({length:7},()=>({cl:'tree'}))},{cell:[1,0],rows:[{bld:{}},{cl:'rock'}]},
    {cell:[0,1],rows:Array.from({length:5},()=>({bld:true}))}];
  const scene=create();scene._blockGrid={C:rules.cell,grid:new Map(cells.map(cell=>[(cell.cell[0]+32768)*65536+cell.cell[1]+32768,cell.rows]))};
  const densities=[];
  for(const x of [-64,-32,0,31.999,32,32.001,64,96])for(const z of [-32,0,32,64])densities.push({position:[x,z],result:scene._ambDensityAt(x,z)});
  scene._blockGrid.grid.clear();
  const retained=scene._ambDensityAt(32,32);
  const places=[];
  for(const ground of [0,1,2])for(const tunnel of [false,true])for(const empty of [false,true]){
    const scene=create(),calls=[],densities={bld:.25,tree:.75},position=[3,-7];
    const entities=empty?[]:[entity('base',[10,0,5],{isStatic:true}),entity('tower',[3,100,-7],{isStatic:true,dead:true}),entity('robot',[3,0,-7])];
    Object.assign(scene,{pos:{x:position[0],z:position[1]},terrain:{tunnelAt:()=>tunnel},_env:{ground},ents:new Map(entities.map((row,i)=>[i,row])),
      audio:{ambOn:true,setAmbience:value=>calls.push(value)},_ambDensityAt:()=>densities});
    scene._updatePlaceAudio();places.push({ground,tunnel,densities,position,entities,result:calls[0]});
  }
  return {rules,fixtures:{audioMoveCategories:categoriesCases,audioSceneMovement:movement,audioSceneDensity:{cells,cases:densities,retained},audioScenePlaces:places}};
}
