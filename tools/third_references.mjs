import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function thirdReferences(d,BattleSim,config,makeRng,source) {
  const {generateCivilian}=await import(pathToFileURL(join(source,'public/js/civilianAppearance.js')).href);
  const {readSrc,grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const name='_clearAroundBunker';
  const clearBunker=new Function('THIRD',`return function ${grabMethod(readSrc('public','js','game.js').replace(/\r\n/g,'\n'),name).trim().slice(name.length)}`)(d.THIRD);
  const template=new BattleSim(config),campClearance=[],campClearCache=[],campSeeds=[],campHomes=[],campBehavior=[],campAggro=[],campMoves=[],campTimers=[],campDeaths=[],campRelease=[];
  const thirdDamage=[],civilianBodies=[],civilianPoints=[],civilianWander=[],civilianMoves=[],civilianSpawns=[],civilianSeeds=[],civilianRespawns=[],civilianInteractions=[],civilianTicks=[],civilianDeaths=[];
  const seeded=(callback,seed=42)=>{
    const original=Math.random,random=makeRng(seed);let draws=0;
    Math.random=()=>{draws++;return random();};
    try{return {result:callback(),draws};}finally{Math.random=original;}
  };
  const mirror=([x,z])=>[x,-z];
  const normalizeCamp=camp=>({side:camp.type,lane:camp.li,x:camp.x,z:-camp.z,exit_angle:camp.exitA});
  const normalized=e=>({kind:e.kind,side:e.side,slot:e.slot??0,x:e.x,z:-e.z,hp:e.hp,max_hp:e.maxHp,
    garrison:!!e.gar,retreat:!!e.ret,seek:!!e.seek,aggro_at:e.aggroAt??0,stun:!!e.stunUntil,slow:!!e.slowUntil,slow_factor:e.slowF??.6,confuse:!!e.confUntil});
  const normalizedCiv=e=>({id:e.id,x:e.x,z:-e.z,yaw:e.ry??0,follow:e.follow??0,follow_time:e.followT,flee:e.flee,flee_ttl:e.fleeTtl,
    pause:e.wpPause,waypoint:e.wp?{x:e.wp[0],z:-e.wp[1]}:null});
  const civilianState=e=>({...normalizedCiv(e),side:e.cs,spy:e.spy,profession:e.prof,hp:e.hp,max_hp:e.maxHp,
    home:mirror(e.home),neutral:!!e.neutral,public_side:e.side??''});
  const base={type:'GUER',li:0,x:0,z:0,exitA:.3,bunker:{id:50},pool:[],bunkerRem:0};
  const body={id:1,kind:'soldier',side:'GUER',tp:1,ci:0,slot:1,x:0,z:0,hp:50,maxHp:100,gar:0,ret:0,seek:0,aggroAt:0};
  const bounds={minX:-1000,maxX:3000,minZ:-1400,maxZ:1400},lanes=[[[0,0],[2000,0]]],basePos={SWARM:[0,0],STEEL:[2000,0]};
  const occ=[[15.999,0,60,2],[16,0,60,2],[20,0,60,2],[10,0,3,12,2,2,0,'joined',0],[60,0,3,12,2,2,0,'joined',0],
    [80,0,3,12,2,2,0,'far',0],[20,0,5,12,4,2,Math.PI/4,'rotated',0],[0,40,3,12,2,2,0,'north',0]];
  const worldContext=camps=>Object.assign(Object.create(template),{_worldSet:false,_wetGrid:{},camps,
    _ingestSlabs:()=>{},_ingestHgt:()=>{},_ingestCover:()=>{},_rebuildLosGrid:()=>{},_registerMapBuildings:()=>{}});
  const obstacleState=shape=>({shape:Array.from(shape),baseY:shape.baseY??null,...(shape.buildingKey?{buildingKey:shape.buildingKey}:{})});
  const baseline=worldContext([]);baseline.setWorld({occ});
  for(const camps of [[],[{x:0,z:0}],[{x:20,z:30}],[{x:0,z:0},{x:80,z:0}]]) {
    const sim=worldContext(camps);sim.setWorld({occ});
    const kept=sim.worldOcc.map(obstacleState),encoded=new Set(kept.map(o=>JSON.stringify(o))),removed=[];
    const obstacles=baseline.worldOcc.map(obstacleState);
    for(let i=0;i<obstacles.length;i++)if(!encoded.has(JSON.stringify(obstacles[i])))removed.push(i);
    const buildings=[...new Set(removed.map(i=>obstacles[i].buildingKey).filter(Boolean))];
    campClearance.push({camps:camps.map(c=>({x:c.x,z:-c.z})),obstacles,result:{removed,buildings,kept}});
  }
  for(const removed of [false,true]) {
    const points=[[.49,.49],[.499,.499],[.5,.5],[-.5,-.5],[-.501,-.501],[.49,.49]],calls=[],rebuild=[];
    const client={terrain:{blockers:[],clearBuildingsAround:(x,z,r)=>{calls.push({x,z,r});return removed;},
      rebuildBlockerTops:()=>rebuild.push('tops'),rebuildClimbs:()=>rebuild.push('climbs')},
      _buildBlockGrid:()=>rebuild.push('grid'),_ambDens:{clear:()=>rebuild.push('ambience')}};
    for(const [x,z] of points)clearBunker.call(client,{x,z:-z});
    campClearCache.push({points,removed,calls,rebuild});
  }
  for(const size of [1,2,3])for(const terrain of ['none','all','north'])for(const seed of [0,42,123456789]) {
    const paths=Array.from({length:size},(_,i)=>lanes[0].map(([x,z])=>[x,z+i*100]));
    const towers=[{id:-1,kind:'tower',x:500,z:0},{id:-2,kind:'tower',x:1500,z:0}];
    const sim=Object.assign(Object.create(template),{lanes:paths,bounds,basePos,ents:new Map(towers.map(e=>[e.id,e])),hazBlockers:[],_cumCache:null,camps:[],
      _terrainBlocked:(x,z)=>terrain==='all'||terrain==='north'&&z>0,
      _spawnCamp:(type,li,x,z,outN)=>sim.camps.push({type,li,x,z,exitA:Math.atan2(-outN[1],-outN[0])})});
    const fixture=seeded(()=>{sim._seedCamps();return sim.camps.map(normalizeCamp);},seed);
    campSeeds.push({seed,terrain,draws:fixture.draws,result:fixture.result,state:{bounds:{...bounds,minZ:-bounds.maxZ,maxZ:-bounds.minZ},
      lanes:paths.map(path=>path.map(mirror)),cumulative:paths.map(path=>{let length=0;return path.map((point,i)=>{if(i)length+=Math.hypot(point[0]-path[i-1][0],point[1]-path[i-1][1]);return length;});}),
      bases:basePos,towers:towers.map(e=>({x:e.x,z:-e.z})),blockers:[]}});
  }
  for(const side of ['GUER','MILI'])for(const angle of [0,.3,Math.PI/2,-Math.PI])for(const slot of [0,1,2,3,4]) {
    const camp={...base,type:side,exitA:angle,x:100,z:50};
    const [x,z]=template._campHome(camp,slot);campHomes.push({camp:normalizeCamp(camp),slot,result:{x,z:-z}});
  }
  for(const kind of ['soldier','rocketeer','heli','bunker'])for(const garrison of [false,true])for(const bunker of [false,true])
    for(const hp of [49,50,99.9,100])for(const distance of [0,7,7.001,26,26.001,90,90.001])for(const retreat of [false,true])for(const occupancy of [0,3]) {
    const e={...body,kind,hp,x:distance,gar:garrison?1:0,ret:retreat?1:0},camp={...base,bunker:bunker?{id:50}:null};
    const sim=Object.assign(Object.create(template),{camps:[camp],_garCount:()=>occupancy});sim._tpBehave(e,.125);
    campBehavior.push({state:normalized({...body,kind,hp,x:distance,gar:garrison?1:0,ret:retreat?1:0}),camp:{...normalizeCamp(camp),bunker},occupancy,result:normalized(e)});
  }
  for(const elapsed of [0,8,8.001])for(const dead of [false,true])for(const hp of [0,100])for(const stealth of [false,true])for(const same of [false,true]) {
    const target={id:2,hp,dead,side:same?'GUER':'STEEL',stealthUntil:stealth?11:0},e={...body,aggro:target,aggroAt:10-elapsed};
    const sim=Object.assign(Object.create(template),{t:10});campAggro.push({state:normalized(e),target:{hp,dead,side:target.side,stealth},result:!!sim._tpAggroTarget(e)});
  }
  for(const kind of ['soldier','heli'])for(const mode of ['home','retreat','seek','aggro','sight'])for(const control of ['none','stun','slow','confuse'])for(const terrain of ['none','enter','inside']) {
    const e={...body,kind,x:50,z:10,ret:mode==='retreat'?1:0,seek:mode==='seek'?1:0,
      stunUntil:control==='stun'?11:0,slowUntil:control==='slow'?11:0,slowF:.3,confUntil:control==='confuse'?11:0};
    const target={id:2,x:500,z:100,hp:100,dead:false,side:'STEEL'},profile={speed:16,range:30,sight:200},blockers=[[51,10,3]];
    const sim=Object.assign(Object.create(template),{t:10,camps:[base],hazBlockers:blockers,_tpAggroTarget:()=>mode==='aggro'?target:null,
      _acquireTarget:()=>mode==='sight'?target:null,_terrainBlocked:(x,z)=>terrain==='inside'||terrain==='enter'&&x!==50});
    sim._tpMove(e,profile,.125);
    campMoves.push({state:normalized({...e,x:50,z:10}),camp:{...normalizeCamp(base),bunker:true},profile,
      target:['aggro','sight'].includes(mode)?{x:500,z:-100}:{},terrain,blockers:blockers.map(([x,z,radius])=>({x,z:-z,radius})),result:{x:e.x,z:-e.z}});
  }
  for(const bunker of [false,true]) {
    const camp={...base,bunker:bunker?{id:50}:null,bunkerRem:.2,pool:[{kind:'soldier',slot:2,rem:.1},{kind:'tank',slot:4,rem:.3}]},spawns=[];
    const sim=Object.assign(Object.create(template),{camps:[camp],_spawnBunker:()=>{spawns.push({kind:'bunker',slot:0});return {id:50};},_spawnCampUnit:(c,i,kind,slot)=>spawns.push({kind,slot})});
    const steps=[];for(const delta of [.125,.125,.125,.125]){spawns.length=0;sim._tickCamps(delta);steps.push({delta,bunker:!!camp.bunker,remaining:camp.bunkerRem,
      pool:camp.pool.map(p=>({kind:p.kind,slot:p.slot,remaining:p.rem})),spawns:spawns.slice()});}campTimers.push({bunker,steps});
  }
  for(const kind of ['bunker','soldier'])for(const cleared of [false,true])for(const freed of [false,true]) {
    const camp={...base,bunker:{id:50},pool:[],freed},e={...body,kind},roster=cleared?[]:[{...body,id:2,gar:1}],released=[];
    const sim=Object.assign(Object.create(template),{camps:[camp],ents:new Map(roster.map(e=>[e.id,e])),_freeCampCivilians:()=>released.push(1)});
    sim._onThirdDeath(e,null);campDeaths.push({kind,cleared,freed,result:{bunker:!!camp.bunker,remaining:camp.bunkerRem,pool:camp.pool.map(p=>({kind:p.kind,slot:p.slot,remaining:p.rem})),
      freed:!!camp.freed,released:released.length,roster:roster.map(normalized)}});
  }
  for(const owner of ['hero','npc','dead','none']) {
    const heroes=[{id:1,pid:1,hero:true,dead:owner==='none',x:10,z:0,side:'STEEL'},{id:2,pid:2,hero:true,dead:owner==='none',x:20,z:0,side:'SWARM'}];
    const attacker=owner==='hero'?heroes[1]:owner==='npc'?{hero:false}:owner==='dead'?{hero:true,pid:2,dead:true}:null,spawned=[];
    const sim=Object.assign(Object.create(template),{heroes:new Map(heroes.map(h=>[h.pid,h])),events:[],_spawnCiv:(cs,spy,prof,pt)=>{
      const civ={id:100+spawned.length,cs,spy,prof,x:pt.x,z:pt.z,follow:null,followT:0,wpPause:Math.random()*d.CIVILIAN.WANDER_PAUSE[1]};spawned.push(civ);return civ;}});
    const fixture=seeded(()=>{sim._freeCampCivilians(base,attacker);return spawned.map(e=>({side:e.cs,spy:e.spy,profession:e.prof,x:e.x,z:-e.z,
      follow:e.follow??0,noRespawn:!!e.noRespawn,home:mirror(e.home),pause:e.wpPause}));});
    campRelease.push({owner,draws:fixture.draws,result:fixture.result,event:sim.events.length?{peer:sim.events[0].pid,count:sim.events[0].n}:null});
  }
  for(const [attackerSide,targetSide] of [['STEEL','GUER'],['GUER',d.SUPER_SIDE],[d.SUPER_SIDE,'GUER'],['GUER','MILI'],['MILI','GUER'],['STEEL','MILI']])
    for(const kind of ['soldier','bunker'])for(const garrison of [false,true])for(const neutral of [false,true]) {
    const by={id:1,pid:1,hero:attackerSide==='STEEL',ch:'t05',side:attackerSide,neutral,x:0,z:0,hp:100},
      target={id:2,kind,side:targetSide,tp:d.isThirdSide(targetSide),gar:garrison,hp:100,armor:0,x:10,z:0};
    const sim=Object.assign(Object.create(template),{t:10,over:false,curWeatherDyn:null,events:[],entangleGroups:[],
      heroes:new Map(by.hero?[[1,by]]:[]),ents:new Map([[1,by],[2,target]]),_dmgOut:()=>{},_vamp:()=>{}});
    sim._damage(target,10,by);
    thirdDamage.push({attackerSide,targetSide,kind,garrison,neutral,result:{hp:target.hp,aggro:target.aggro?.id??0,aggro_at:target.aggroAt??0,
      assists:Object.keys(target.asst??{}).map(Number),focus:by.lastHitTargetId??0}});
  }
  for(const seed of [0,1,42,123456789,4294967303])for(const profession of [0,3,10,19])civilianBodies.push({seed,profession,body:d.civilianBody(seed),appearance:generateCivilian(seed,profession),
    radius:d.hitR({kind:'civilian',civ:true,id:seed}),height:d.hitH({kind:'civilian',civ:true,id:seed})});
  for(const spy of [false,true])for(const side of ['SWARM','STEEL'])for(const profession of [0,19]) {
    const sim=Object.assign(Object.create(template),{ents:new Map()});
    const fixture=seeded(()=>civilianState(sim._spawnCiv(side,spy,profession,{x:10,z:100})));
    civilianSpawns.push({spy,side,profession,draws:fixture.draws,speed:d.civSpeed(spy),result:fixture.result});
  }
  for(const size of [1,2,3])for(const terrain of ['none','all','north'])for(const seed of [0,42,123456789]) {
    const paths=Array.from({length:size},(_,i)=>lanes[0].map(([x,z])=>[x,z+i*100]));
    const sim=Object.assign(Object.create(template),{bounds,lanes:paths,basePos,hazBlockers:[],ents:new Map(),
      _terrainBlocked:(x,z)=>terrain==='all'||terrain==='north'&&z>0});
    const fixture=seeded(()=>{sim._seedCivilians();return [...sim.ents.values()].map(civilianState);},seed);
    civilianSeeds.push({seed,terrain,draws:fixture.draws,result:fixture.result,state:{bounds:{...bounds,minZ:-bounds.maxZ,maxZ:-bounds.minZ},
      lanes:paths.map(path=>path.map(mirror)),bases:basePos,towers:[],blockers:[]}});
  }
  for(const terrain of ['none','all']) {
    const sim=Object.assign(Object.create(template),{t:10,bounds,lanes,basePos,hazBlockers:[],ents:new Map(),heroes:new Map(),events:[],
      civRespawns:[{cs:'STEEL',spy:true,at:10},{cs:'SWARM',spy:false,at:11},{cs:'SWARM',spy:true,at:9}],_terrainBlocked:()=>terrain==='all'});
    const fixture=seeded(()=>{sim._tickCivilians(.125);return {actors:[...sim.ents.values()].map(civilianState),
      pending:sim.civRespawns.map(r=>({side:r.cs,spy:r.spy,at:r.at}))};});
    civilianRespawns.push({terrain,draws:fixture.draws,result:fixture.result});
  }
  for(const terrain of ['none','all','north'])for(const seed of [0,42,123456789]) {
    const sim=Object.assign(Object.create(template),{bounds,lanes,basePos,hazBlockers:[[400,100,40]],ents:new Map(),_terrainBlocked:(x,z)=>terrain==='all'||terrain==='north'&&z>0});
    const state={bounds:{...bounds,minZ:-bounds.maxZ,maxZ:-bounds.minZ},lanes:lanes.map(path=>path.map(mirror)),bases:basePos,towers:[],blockers:[{x:400,z:-100,radius:40}]};
    const fixture=seeded(()=>sim._civPoint(),seed);civilianPoints.push({seed,terrain,state,draws:fixture.draws,result:fixture.result?{x:fixture.result.x,z:-fixture.result.z}:null});
    const walk=seeded(()=>sim._civWander({home:[400,100]}),seed);civilianWander.push({seed,terrain,state,home:[400,-100],draws:walk.draws,result:{x:walk.result[0],z:-walk.result[1]}});
  }
  for(const away of [false,true])for(const terrain of ['none','all','enter'])for(const goal of [[0,0],[.0001,0],[3,4],[5000,2000]]) {
    const e={x:0,z:0,ry:0},sim=Object.assign(Object.create(template),{bounds,_terrainBlocked:(x,z)=>terrain==='all'||terrain==='enter'&&x!==0});
    const moved=sim._moveCiv(e,goal[0],goal[1],100,10,away);civilianMoves.push({away,terrain,goal:mirror(goal),bounds:{...bounds,minZ:-bounds.maxZ,maxZ:-bounds.minZ},
      moved,result:{x:e.x,z:-e.z,yaw:e.ry}});
  }
  for(const action of ['follow','away','other'])for(const distance of [0,d.CIVILIAN.INTERACT_R*1.25,d.CIVILIAN.INTERACT_R*1.25+.001])for(const dead of [false,true]) {
    const hero={pid:1,side:'STEEL',dead,x:0,z:0},civ={id:50,civ:true,hp:40,x:distance,z:0,cs:'SWARM',follow:2,followT:100,flee:true,fleeTtl:3,fleeX:1,fleeZ:2};
    const sim=Object.assign(Object.create(template),{over:false,heroes:new Map([[1,hero]]),ents:new Map([[50,civ]]),events:[]});sim.civInteract(1,50,action);
    civilianInteractions.push({action,distance,dead,result:{follow:civ.follow??0,follow_time:civ.followT,flee:civ.flee,flee_ttl:civ.fleeTtl,flee_point:[civ.fleeX,-civ.fleeZ]},
      events:sim.events.map(e=>({action:e.act,peer:e.pid}))});
  }
  for(const mode of ['wander','follow','enemy','lost','dead','flee','fleeExpired','aid']) {
    const hero={id:1,pid:1,side:'STEEL',x:mode==='lost'?300:30,z:0,dead:mode==='dead'},civ={id:50,civ:true,spy:false,prof:0,cs:mode==='enemy'?'SWARM':'STEEL',
      x:0,z:100,ry:0,home:[0,100],wp:null,wpPause:0,follow:['follow','enemy','lost','dead','aid'].includes(mode)?1:null,
      followT:mode==='aid'?d.CIVILIAN.FOLLOW_REWARD_S-.1:0,flee:mode.startsWith('flee'),fleeTtl:mode==='fleeExpired'?.05:1,fleeX:20,fleeZ:100};
    const rewards=[];
    const sim=Object.assign(Object.create(template),{t:10,bounds,lanes,basePos,hazBlockers:[],heroes:new Map([[1,hero]]),ents:new Map([[50,civ]]),events:[],civRespawns:[],
      _terrainBlocked:()=>false,_grantReward:(body,reward,mul)=>{rewards.push({peer:body.pid,reward,multiplier:mul});return {r:reward,hp:1,sp:2};}});
    const fixture=seeded(()=>{sim._tickCivilians(.125);return {actors:[...sim.ents.values()].map(normalizedCiv),rewards,
      events:sim.events.map(e=>({peer:e.pid,profession:e.prof}))};});civilianTicks.push({mode,draws:fixture.draws,result:fixture.result});
  }
  for(const side of ['STEEL','SWARM'])for(const spy of [false,true])for(const noRespawn of [false,true]) {
    const hero={id:1,pid:1,hero:true,side:'STEEL',money:10},civ={id:50,civ:true,kind:'civilian',cs:side,spy,noRespawn,side:null,x:0,z:0,hp:0};
    const sim=Object.assign(Object.create(template),{t:10,events:[],ents:new Map([[50,civ]]),civRespawns:[]});sim._kill(civ,hero);
    civilianDeaths.push({side,spy,noRespawn,result:{money:hero.money,events:sim.events.map(e=>e.e),respawns:sim.civRespawns.map(e=>({side:e.cs,spy:e.spy,at:e.at})),
      value:sim.events.find(e=>e.e==='civkill')?.v??0}});
  }
  return {campClearance,campClearCache,campSeeds,campHomes,campBehavior,campAggro,campMoves,campTimers,campDeaths,campRelease,thirdDamage,civilianBodies,civilianPoints,civilianWander,civilianMoves,civilianSpawns,civilianSeeds,civilianRespawns,civilianInteractions,civilianTicks,civilianDeaths};
}
