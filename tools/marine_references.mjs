import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export function sourceSeaWaveState(toon, THREE, grabFn) {
  const declaration=/export const WIND = (\{[\s\S]*?\n\});/.exec(toon);
  if(!declaration)throw new Error('Missing original marine wind declarations');
  const WIND=new Function('return ('+declaration[1]+');')();
  const vectors=(count,initial=[0,0,0,0])=>({value:Array.from({length:count},()=>new THREE.Vector4(...initial))});
  const sources=vectors(WIND.SEA_SOURCE_N),shapes=vectors(WIND.SEA_SOURCE_N);
  const setSources=new Function('WIND','_seaSources','_seaSourceShape',grabFn(toon,'setSeaWaveSources')+'\nreturn setSeaWaveSources;')(WIND,sources,shapes);
  const packet=()=>({sources:sources.value.map(v=>v.toArray()),shapes:shapes.value.map(v=>v.toArray())});
  return {WIND,setSources,packet};
}

export async function marineReferences(source) {
  const load=path=>import(pathToFileURL(join(source,path)).href);
  const {readSrc,grabFn}=await load('tools/audit_src.mjs');
  const THREE=await load('out/forest_review/three.module.js');
  const toon=readSrc('public','js','toon.js'),game=readSrc('public','js','game.js');
  const {WIND,setSources,packet}=sourceSeaWaveState(toon,THREE,grabFn);
  const vectors=(count,initial)=>({value:Array.from({length:count},()=>new THREE.Vector4(...initial))});
  const vessel=(i,extra={})=>({x:i*3-10,z:7-i,dx:3,dz:4,length:10+i,beam:2,speed:i%3,...extra});
  const calls=[Array.from({length:WIND.SEA_SOURCE_N+5},(_,i)=>vessel(i)),
    [null,3,{},vessel(0,{dx:0,dz:0}),vessel(1,{dx:1e-6,dz:0}),vessel(2,{dx:1.000001e-6,dz:0}),
      vessel(3,{length:0}),vessel(4,{beam:-1}),vessel(5,{speed:-1}),vessel(6,{x:'1'}),vessel(7,{speed:0}),vessel(8,{dx:-4,dz:3})],
    [],null,{},[vessel(22),vessel(23,{dx:3e30,dz:4e30})],Array.from({length:WIND.SEA_SOURCE_N+2},(_,i)=>vessel(i,{dx:0,dz:-2}))];
  const waves=[];
  for(const records of calls){setSources(records);waves.push({records,...packet()});}
  const scanStart='if (!this._swampCells && this.terrain?.waterY != null) {';
  const scanEnd='stepSwampRipples(this._swampCells, dt);';
  const start=game.indexOf(scanStart),end=game.indexOf(scanEnd,start);
  if(start<0||end<0)throw new Error('Missing original incremental swamp scan');
  const scanSource=game.slice(start,end+scanEnd.length);
  const scans=[];
  for(const mode of ['mixed','dry','small','no_water','delayed_water','tidal']) {
    const time={value:0},ripple=vectors(WIND.SWAMP_RIPPLE_N,[0,0,-999,0]);
    const run=new Function('WIND','_windT','_ripple',
      'let _rippleIdx=0,_rippleCD=0;\n'+grabFn(toon,'rippleHash')+'\n'+grabFn(toon,'stepSwampRipples')+
      '\nreturn {step:stepSwampRipples,state:()=>({index:_rippleIdx,cooldown:_rippleCD,packets:_ripple.value.map(v=>v.toArray())})};')(WIND,time,ripple);
    const terrain={minX:-43,maxX:mode==='small'?-40:78,minZ:-61,maxZ:mode==='small'?-59:164,waterY:['no_water','delayed_water'].includes(mode)?null:0};
    const bounds={...terrain};
    const code=(_t,x,z)=>mode==='dry'?0:(Math.floor((x+43)/20)+Math.floor((z+61)/20))%3===0&&(mode!=='tidal'||_t.waterY>0)?2:1;
    const context={terrain};
    const scan=new Function('terrainEnvCode','stepSwampRipples','return function(dt){'+scanSource+'};')(code,run.step);
    const frames=[];
    for(let i=0;i<140;i++) {
      const delta=[0,.016,.25,7,-1,.1][i%6];
      if(mode==='delayed_water'&&i===3)terrain.waterY=0;
      if(mode==='tidal')terrain.waterY=i%2;
      time.value+=Number.isFinite(delta)?Math.min(.25,Math.max(0,delta)):0;
      scan.call(context,delta);
      frames.push({delta,now:time.value,waterY:terrain.waterY,waveAmp:[0,.001,.0011,1][i%4],ready:Array.isArray(context._swampCells),cells:(context._swampCells||[]).map(cell=>({...cell})),
        pending:(context._swampAcc||[]).map(cell=>({...cell})),nextZ:context._swampZ??null,...run.state()});
    }
    scans.push({mode,bounds,frames});
  }
  const hashes=[0,1,-1,0xffffffff,0x80000000,0x5bd1e995,0xa7c3].map(value=>({value,
    result:new Function(grabFn(toon,'rippleHash')+'\nreturn rippleHash;')()(value)}));
  return {marineRules:WIND,marineWaveProgram:waves,marineRipplePrograms:scans,marineRippleHashes:hashes};
}
