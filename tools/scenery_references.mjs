export function sceneryReferences(d,BattleSim,config,makeRng,surfaceRules) {
  const template=new BattleSim(config),sceneryHeights=[],sceneryStrikes=[],sceneryFires=[];
  for(const encoded of [
    {minX:-20,minZ:-30,cell:20,cols:3,rows:2,minH:-5,data:[0,10,100,300,1000,3000].map(value=>d.hgtEnc(value,-5)).join('')},
    {minX:0,minZ:0,cell:20,cols:1,rows:1,minH:0,data:d.hgtEnc(12.37,0)},
    {minX:0,minZ:0,cell:0,cols:1,rows:1,minH:0,data:'AA'},
    {minX:0,minZ:0,cell:20,cols:2,rows:2,minH:0,data:'AA'},
    {minX:0,minZ:0,cell:20,cols:1,rows:1,minH:0,data:'!!'}]) {
    const sim=Object.assign(Object.create(template),{_hgtGrid:null});sim._ingestHgt({hgt:encoded});
    for(const x of [-100,-20,0,10,20,40,100])for(const z of [-100,-30,-10,0,30,100])
      sceneryHeights.push({encoded,x,z,result:sim._hgtAt(x,-z)});
  }
  for(const seed of [0,42,123456789])for(const mode of ['flat','unknown','wet','wet_edge','slab','slab_edge','slope_limit','slope_over','circle','box','box_miss','rain','snow','cap']) {
    const bounds={minX:-100,maxX:100,minZ:-100,maxZ:100},preview=makeRng(seed);
    const cx=-100+preview()*200,cz=-100+preview()*200;
    const radius=surfaceRules.strikeR;
    const obstacles=[];
    if(mode==='circle')obstacles.push([cx,cz,6,5]);
    if(mode==='box'||mode==='box_miss')obstacles.push([cx+(mode==='box_miss'?3:0),cz,6,5,2,4,1,0]);
    const dynamics={effectiveRain:mode==='rain'?.001:0,effectiveSnow:mode==='snow'?.001:0};
    const height=(x,_z)=>mode==='unknown'?null:mode==='slope_limit'?x*surfaceRules.flatGrade:mode==='slope_over'?x*(surfaceRules.flatGrade+.000001):0;
    const wet=(x,_z)=>mode==='wet'?1:mode==='wet_edge'&&x>cx+radius-.01?1:0;
    const level=(x,_z)=>mode==='slab'?1:mode==='slab_edge'&&x>cx+radius-.01?2:0;
    const added=[],shocks=[];
    const sim=Object.assign(Object.create(template),{bounds,t:10,weatherScars:[],_hgtGrid:{},_wetGrid:{},worldOcc:obstacles,
      curWeatherDyn:dynamics,_fires:mode==='cap'?Array(40).fill({}):[],events:[],_hgtAt:height,_wetAt:wet,_slabLevAt:level,
      _lightningShockwave:(x,z)=>shocks.push([x,-z]),_rebuildAvoidZones(){},_add:actor=>{added.push(actor);return actor;}});
    sim._strikeWeatherSurface(makeRng(seed));
    const strike=sim.events.find(event=>event.e==='lightning_strike')?.pts[0];
    sceneryStrikes.push({seed,mode,cx,cz:-cz,bounds,dynamics,obstacles:obstacles.map(shape=>({shape,baseY:null})),count:mode==='cap'?40:0,
      result:strike?{x:strike.x,y:strike.y,z:-strike.z,radius,fire:added.length>0}:null,
      ttl:added[0]?.ttl??null,scale:added[0]?.sc??null,shocks});
  }
  for(const weather of [{rain:0,snow:0,wind:0},{rain:0,snow:0,wind:100},
    {rain:100,snow:0,wind:100,effectiveRain:0},{rain:80,snow:0,wind:80,effectiveRain:.1},
    {rain:0,snow:100,wind:80,effectiveSnow:.1}])for(const lightning of [false,true])for(const lifetime of [null,.05,.25,20]) {
    const actors=['robot','drone','morph','drone'].map((kind,index)=>({id:index+1,pid:index+1,kind,hero:true,
      ch:Object.keys(d.CHARACTERS).find(key=>d.CHARACTERS[key].kind===kind),side:'STEEL',x:0,z:0,y:[0,20,.051,50][index],hp:100,dead:false}));
    const fires=['fire','forestfire','grassfire','factoryfire'].map((kind,index)=>({id:50+index,kind,x:0,z:0,sc:1,ttl:lifetime,lightningFire:lightning}));
    const sim=Object.assign(Object.create(template),{t:10,ents:new Map(fires.map(f=>[f.id,f])),_fires:fires,events:[],loots:[],curWeatherDyn:weather,
      _allBodies:function*(){yield*actors;},_fireBurn:(actor,amount)=>burns.push({id:actor.id,amount})});
	 sim._rebuildAvoidZones();
    let burns=[];const steps=[];
    for(const delta of [.125,.125,1,2]) {
      sim.t+=delta;sim.events=[];burns=[];sim._tickHazards(delta);
      steps.push({delta,now:sim.t,burns:structuredClone(burns),fires:sim._fires.map(f=>({id:f.id,ttl:f.ttl})),
        reports:actors.map(a=>({id:a.id,at:a._burnAt||0})),avoid:sim._avoidZones.map(zone=>({x:zone.x,z:-zone.z,radius:zone.r}))});
    }
    sceneryFires.push({weather,lightning,lifetime,actors,steps});
  }
  return {sceneryHeights,sceneryStrikes,sceneryFires};
}
