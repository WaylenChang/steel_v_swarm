import {encodeSourceNumericPart} from './source_numeric_transfer.mjs';

const point=values=>values.map(Math.fround);
const entity=(kind,position,weights=null,extra={})=>({kind,mesh:{visible:true,
  position:Object.fromEntries(['x','y','z'].map((axis,index)=>[axis,point(position)[index]]))},
  loco:weights?{w:{walk:weights[0],run:weights[1],air:weights[2]??0}}:null,...extra});

export function audioScenePrecisionPrograms(characters) {
  const camera={position:[0,0,0],right:[1,0,0]},movement=[];
  const add=(name,entities,extra={})=>movement.push({name,camera,entities,selfBed:false,low:false,ownWeights:null,...extra});
  for(const position of [[200,0,0],[200,0,.001],[200,.001,0],[199.99998474121094,0,0],[200.00001525878906,0,0]])
    add('range:'+position.join(','),[entity('heli',position,[.2,.7])]);
  add('nearest',[entity('heli',[20,0,.001],[0,.9]),entity('heli',[20,0,0],[0,0])]);
  add('nearest-reversed',movement.at(-1).entities.toReversed());
  add('ties',[entity('heli',[20,0,0],[0,.9]),entity('heli',[-20,0,0],[0,0])]);
  add('self-excluded',[entity('tank',[900,900,900],null,{isSelf:true})]);
  add('self-included',movement.at(-1).entities,{selfBed:true,ownWeights:{walk:.1,run:.9}});
  add('low-power',[entity('heli',[20,0,0],[0,1])],{low:true});
  add('excluded',[entity('tank',[0,0,0],null,{dead:true}),entity('heli',[0,0,0],null,{isStatic:true}),
    entity('drone',[0,0,0],null,{mesh:{visible:false,position:{x:0,y:0,z:0}}})]);
  let seed=0x51de;
  const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
  for(let index=0;index<96;index++) {
    const position=point([random()*1000-500,random()*100-50,random()*1000-500]);
    const right=point([Math.cos(index),0,Math.sin(index)]);
    add('native:'+index,['heli','tank','drone','heli'].map(kind=>entity(kind,
      position.map(value=>value+random()*260-130),[random(),random()])),{camera:{position,right}});
  }
  for(const ch of Object.keys(characters))for(const flies of [false,true])for(const air of [0,.5,.500001,1])
    add('hero:'+ch+':'+flies+':'+air,[entity('robot',[8,.125,-10],[.3,.2,air],{hero:true,ch,flies})]);
  const ch=Object.keys(characters)[0];
  add('stomp-nearest',[entity('robot',[20,0,.001],[0,.9,0],{hero:true,ch}),
    entity('robot',[20,0,0],[0,0,0],{hero:true,ch})]);
  add('stomp-reversed',movement.at(-1).entities.toReversed());
  add('stomp-self',[entity('robot',[900,900,900],[0,0,0],{hero:true,ch,isSelf:true})],
    {selfBed:true,ownWeights:{walk:.1,run:.9}});
  add('stomp-null',[entity('robot',[20,0,0],null,{hero:true,ch})]);
  add('stomp-low',movement.at(-1).entities,{low:true});
  const cells=[{cell:[-1,0],rows:[...Array.from({length:30},()=>({bld:true,cl:'tree'})),{cl:'tree'}]},
    {cell:[0,0],rows:Array.from({length:7},()=>({cl:'tree'}))},
    {cell:[1,0],rows:[{bld:{}},{cl:'rock'}]},
    {cell:[0,1],rows:Array.from({length:5},()=>({bld:true}))}];
  const positions=[];
  for(const x of [-64,-32.000003814697266,-32,-31.999998092651367,-1e-20,0,1e-20,
    31.999998092651367,32,32.000003814697266,64,96])
    for(const z of [-32,-1e-20,0,31.999998092651367,32,64])positions.push(point([x,z]));
  const places=[];
  for(const ground of [0,1,2])for(const tunnel of [false,true])for(const position of positions.filter((_,index)=>index%6===0))
    places.push({ground,tunnel,position,entities:[entity('base',[20.001,100,.001],null,{isStatic:true}),
      entity('tower',[-20,0,3.125],null,{isStatic:true}),entity('tank',[0,0,0]),
      entity('base',[position[0],0,position[1]],null,{isStatic:true,dead:true})]});
  places.push({ground:0,tunnel:false,position:[0,0],entities:[]});
  return {movement,cells,positions,places};
}

// The original methods and literal character profiles run without unrelated
// data-module initialization or combat RNG. Terrain responses remain explicit probes.
export function runAudioScenePrecision(methods,programs,cellSize,characters,encode) {
  const result={movement:[],density:[],places:[]};
  const make=(selfBed,queries=[])=>new (new Function('CHARACTERS','SELF_BED','terrainEnvCode',
    'return class {\n'+Object.values(methods).join('\n')+'\n};')(
      characters,selfBed,(_terrain,x,z)=>{queries.push([x,z]);return x>=0&&z<=0?1:2;}))();
  const xyz=values=>Object.fromEntries(['x','y','z'].map((axis,index)=>[axis,values[index]]));
  for(const program of programs.movement) {
    const queries=[],scene=make(program.selfBed,queries),calls=[];
    Object.assign(scene,{audio:{_dead:false,lowPower:program.low,
      setMove:(category,...parameters)=>calls.push({category,parameters:encode(parameters)})},
      camera:{position:xyz(program.camera.position),matrixWorld:{elements:program.camera.right}},
      ents:new Map(program.entities.map((value,index)=>[index,value])),_selfW:program.ownWeights,
      _env:{ground:1},_updatePlaceAudio(){}});
    scene._updateMoveAudio();result.movement.push({calls,queries:queries.length?encode(queries):[]});
  }
  const density=make(false);
  density._blockGrid={C:cellSize,grid:new Map(programs.cells.map(cell=>[
    (cell.cell[0]+32768)*65536+cell.cell[1]+32768,cell.rows]))};
  for(const position of programs.positions) {
    const value=density._ambDensityAt(...position);
    result.density.push(encode([value.bld,value.tree]));
  }
  density._blockGrid.grid.clear();
  const retained=density._ambDensityAt(32,32);
  result.retained=encode([retained.bld,retained.tree]);
  for(const program of programs.places) {
    const scene=make(false),calls=[];
    Object.assign(scene,{audio:{ambOn:true,setAmbience:value=>calls.push(value)},
      pos:{x:program.position[0],z:program.position[1]},_env:{ground:program.ground},
      terrain:{tunnelAt:()=>program.tunnel},_ambDensityAt:()=>({bld:.25,tree:.75}),
      ents:new Map(program.entities.map((value,index)=>[index,value]))});
    scene._updatePlaceAudio();
    const value=calls[0];
    result.places.push({unboundedCamp:value.camp===Infinity,parameters:encode([
      value.tunnel,value.water,value.swamp,value.camp===Infinity?0:value.camp,value.urban,value.forest])});
  }
  return result;
}

export const sceneNumericPart=encodeSourceNumericPart;
