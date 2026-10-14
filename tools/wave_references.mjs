// Original producers and lane stepping supply the source wave geometry and control oracle.
export function waveReferences(d, BattleSim, config, cumLen, pointAt, makeRng) {
  const spawn=BattleSim.prototype._spawnLaneWave.toString(),advance=BattleSim.prototype._advance.toString();
  const tail=/lead - i \* ([\d.]+)/.exec(spawn),jitter=/\(Math.random\(\) - 0\.5\) \* ([\d.]+)/.exec(spawn);
  const convergence=/e\.x = x \+ \(e\.x - x\) \* ([\d.]+)/.exec(advance),push=/UNIT_PUSH_R = ([\d.]+)/.exec(advance);
  const structures=/STRUCT_R = \{ tower: ([\d.]+), base: ([\d.]+) \}/.exec(advance);
  if(!tail||!jitter||!convergence||!push||!structures)throw new Error('Source wave placement/movement seams missing');
  const rules={composition:d.waveComp(),spacing:d.waveSpacingM(),tail_spacing:Number(tail[1]),jitter:Number(jitter[1]),
    convergence:Number(convergence[1]),unit_push:Number(push[1]),structure_radius:{tower:Number(structures[1]),base:Number(structures[2])}};
  const template=new BattleSim(config),lanes=[[[0,0],[120,0],[120,160],[400,160]]];
  const context=()=>Object.assign(Object.create(template),{t:10,over:false,events:[],ents:new Map(),heroes:new Map(),
    lanes:structuredClone(lanes),_cumCache:null,creepUpg:{STEEL:[0],SWARM:[0]},_structs:[],hazBlockers:[],_pushBuckets:null,
    curWeatherDyn:{wind:0,windDir:[1,0]},weatherSurface:{}});
  const seeded=callback=>{
    const original=Math.random,random=makeRng(42);let draws=0;
    Math.random=()=>{draws++;return random();};
    try{return {value:callback(),draws};}finally{Math.random=original;}
  };
  const wavePolyline=[];
  for(const points of [lanes[0],[[0,0],[0,0],[60,80]],[[0,0],[60,80]],[[0,0],[0,100]]]) {
    const cumulative=cumLen(points);
    for(const distance of [-10,0,1,60,100,120,121,280,560,1000]) {
      const p=pointAt(points,cumulative,distance);
      wavePolyline.push({points:points.map(p=>[p[0],-p[1]]),cumulative,distance,point:{x:p[0],z:-p[1]}});
    }
  }
  const waveSpawn=[];
  for(const side of ['STEEL','SWARM'])for(const lead of [0,d.GAME.WAVE_SPAWN_OFF_M,d.GAME.WAVE_SPAWN_OFF_M+d.waveSpacingM(),2000])for(const level of [0,10]) {
    const s=context(),actors=[];s.creepUpg[side][0]=level;
    s._add=e=>{actors.push(e);return e;};
    const result=seeded(()=>s._spawnLaneWave(0,side,-1,lead));
    waveSpawn.push({side,lead,level,draws:result.draws,points:lanes[0].map(p=>[p[0],-p[1]]),
      actors:actors.map(e=>({kind:e.kind,side:e.side,progress:e.prog,x:e.x,z:-e.z,y:e.y,hp:e.hp,multiplier:e.cu||1,wave:e.wv}))});
  }
  const wavePrefill=[];
  for(const defSide of [null,'STEEL','SWARM'])for(const towers of ['both','steel','none']) {
    const s=context(),calls=[];s.defSide=defSide;
    s.towerSites=[[{frac:.2,SWARM:towers==='both',STEEL:towers!=='none'},{frac:.4,SWARM:towers==='both',STEEL:towers!=='none'}]];
    if(towers==='none')s.towerSites=[[]];
    s._spawnLaneWave=(lane,side,wave,lead)=>calls.push({lane,side,wave,lead});
    s._prefillLanes();
    wavePrefill.push({defSide,towers,calls});
  }
  const waveAnchors=[];
  for(const engaged of [false,true])for(const dead of [false,true]) {
    const s=context(),actors=[{id:1,kind:'soldier',side:'STEEL',lane:0,wv:1,hp:dead?0:100,prog:30,_eng:engaged},
      {id:2,kind:'tank',side:'STEEL',lane:0,wv:1,hp:100,prog:60},
      {id:3,kind:'soldier',side:'SWARM',lane:0,wv:-1,hp:100,prog:40},
      {id:4,kind:'robot',side:'STEEL',hero:true,lane:0,wv:1,hp:100,prog:1},
      {id:5,kind:'soldier',side:'STEEL',lane:null,wv:1,hp:100,prog:1}];
    s.ents=new Map(actors.map(e=>[e.id,e]));
    waveAnchors.push({engaged,dead,result:Object.fromEntries(s._waveAnchors())});
  }
  const waveMovement=[];
  for(const side of ['STEEL','SWARM'])for(const status of ['normal','stun','slow','confuse','slow_confuse'])for(const anchor of [null,0,30,60])
    for(const obstacles of [false,true]) {
      const s=context(),e={id:1,kind:'soldier',side,lane:0,wv:1,hp:100,prog:60,x:side==='SWARM'?64:335,z:side==='SWARM'?4:156};
      if(status==='stun')e.stunUntil=20;
      if(status.includes('slow')){e.slowUntil=20;e.slowF=.6;}
      if(status.includes('confuse'))e.confUntil=20;
      s.ents.set(1,e);s._anchors=anchor==null?new Map():new Map([[`${side}|0|1`,anchor]]);
      if(obstacles) {
        s._structs=[{kind:'tower',x:70,z:0},{kind:'base',x:330,z:160}];
        s.hazBlockers=[[60,0,6]];
        s.ents.set(2,{id:2,kind:'soldier',side,lane:0,hp:100,x:e.x-2,z:e.z});
      }
      const input={x:e.x,z:-e.z,progress:e.prog,side},steps=[];
      for(const delta of [d.GAME.TICK_MS/1000,d.GAME.TICK_MS/1000,.5]) {
        s._advance(e,d.UNITS.soldier,delta);
        steps.push({delta,x:e.x,z:-e.z,progress:e.prog});
      }
      waveMovement.push({side,status,anchor,obstacles,input,points:lanes[0].map(p=>[p[0],-p[1]]),
        structures:s._structs.map(e=>({kind:e.kind,x:e.x,z:-e.z})),blockers:s.hazBlockers.map(([x,z,radius])=>({x,z:-z,radius})),
        allies:[...s.ents.values()].filter(o=>o!==e).map(o=>({x:o.x,z:-o.z})),steps});
  }
  return {rules,fixtures:{wavePolyline,waveSpawn,wavePrefill,waveAnchors,waveMovement}};
}
