export function sceneReferences(d,BattleSim,config,makeRng) {
  const template=new BattleSim(config),sceneMath=[],sceneGeneration=[],sceneCollapse=[],sceneLoot=[],scenePickups=[],sceneMines=[],sceneAmbush=[],sceneRelays=[];
  const seeded=(callback,seed=42)=>{
    const original=Math.random,random=makeRng(seed);let draws=0;
    Math.random=()=>{draws++;return random();};
    try{return {value:callback(),draws};}finally{Math.random=original;}
  };
  for(const kind of [...Object.keys(d.SCENE_STRUCT.TYPE),'fire'])for(const radius of [0,8,64])for(const scale of [-1,0,.75,1,1.35])
    for(const x of [-1.05,-.05,0,.05,100])for(const z of [-1.05,-.05,0,.05,100]) {
      const hp=d.sceneHpFor(kind,radius,scale,x,z);
      sceneMath.push({kind,radius,scale,x,z:-z,hash:d.sceneHash01(x,z,kind),physical:d.sceneIsPhysical(kind),hp,
        armor:d.sceneArmorFor(kind,hp),electric:d.sceneIsEV(x,z),fire:d.sceneFireTtl(hp),vehicleFire:d.sceneVehicleFireTtl(d.sceneIsEV(x,z))});
    }
  const lanes=[[[0,0],[500,0],[500,500],[1400,500]]],bases={SWARM:[0,0],STEEL:[1400,500]},bounds={minX:-400,maxX:1800,minZ:-400,maxZ:1000};
  const mirror=point=>[point[0],-point[1]];
  const towers=[{id:-1,kind:'tower',x:750,z:0},{id:-2,kind:'tower',x:1000,z:500}];
  const nativeState=sim=>({actors:[...sim.ents.values()].filter(e=>e.kind!=='tower').map(e=>({kind:e.kind,x:e.x,z:-e.z,scale:e.sc,hp:e.hp,armor:e.armor??0,
      invulnerable:!!e.inv,vehicle:!!e.veh,electric:!!e.ev})),blockers:sim.hazBlockers.map(([x,z,radius])=>({x,z:-z,radius})),
      mines:sim.mines.map(([x,z])=>({x,z:-z})),relays:sim._relays.map(e=>({kind:e.kind,x:e.x,z:-e.z}))});
  for(const mix of [null,{urban:.8,green:.1,wet:.1},{bare:.8,wet:.2}])for(const wet of [false,true])for(const prune of [false,true]) {
    let entityId=0;
    const corridors=prune?[[350,-300,350,800,20,1],[900,-300,900,800,12,0]]:[];
    const sim=Object.assign(Object.create(template),{config:{...config,venue:{mix}},ents:new Map(towers.map(e=>[e.id,e])),lanes,basePos:bases,bounds,
      _cumCache:null,_turnCache:null,_wetAt:(x,z)=>wet&&x>1100&&z>650?1:0,_add:e=>{e.id=++entityId;sim.ents.set(e.id,e);return e;}});
    const result=seeded(()=>{sim._seedMines();sim._seedHazards();sim._seedVehicles();sim._ensureConnectivity();sim._seedAASites();sim._seedRelays();
      sim._fires=[...sim.ents.values()].filter(e=>['fire','forestfire','grassfire','factoryfire'].includes(e.kind));sim._pruneCorridors(corridors);return nativeState(sim);});
    sceneGeneration.push({mix:mix||{},wet,bounds:{minX:bounds.minX,maxX:bounds.maxX,minZ:-bounds.maxZ,maxZ:-bounds.minZ},
      lanes:lanes.map(lane=>lane.map(mirror)),bases:Object.fromEntries(Object.entries(bases).map(([key,value])=>[key,mirror(value)])),
      towers:towers.map(e=>({x:e.x,z:-e.z})),corridors,turns:lanes.map(lane=>d.laneTacticsXZ(lane).turns),draws:result.draws,result:result.value});
  }
  for(const kind of Object.keys(d.SCENE_STRUCT.TYPE))for(const scale of [.75,1,1.35])for(const electric of [false,true])for(const capped of [false,true]) {
    const actor={id:1,kind,x:12,z:8,sc:scale,hp:0,maxHp:d.sceneHpFor(kind,d.HAZARDS[kind].r,scale,12,8),ev:electric};
    const spawned=[];
    const sim=Object.assign(Object.create(template),{ents:new Map([[1,actor]]),events:[],hazBlockers:[[12,8,d.HAZARDS[kind].r*scale],[12,8,100]],
      _fires:capped?Array(40).fill({kind:'fire'}):[],_add:e=>{spawned.push(e);return e;}});
    sim._collapseScene(actor,d.sceneIsVehicle(kind)?d.sceneVehicleFireTtl(electric):null);
    sceneCollapse.push({kind,scale,electric,capped,maxHp:actor.maxHp,blockers:sim.hazBlockers.map(([x,z,radius])=>({x,z:-z,radius})),
      fires:spawned.map(e=>({kind:e.kind,scale:e.sc,ttl:e.ttl})),collapsed:!!actor.collapsed});
  }
  for(const seed of [0,42,123456789])for(const treasure of [0,.5,1,2]) {
    const original=Math.random,random=makeRng(seed);let draws=0;
    Math.random=()=>{draws++;return random();};
    try {
      const sim=Object.assign(Object.create(template),{loots:[]});sim._spawnLoot(12,8,treasure);const loot=sim.loots[0];
      sceneLoot.push({seed,treasure,draws,result:{x:loot.x,z:-loot.z,ttl:loot.ttl,...(loot.ammo?{ammo:true}:loot.af?{affix:loot.af}:{value:loot.v})}});
    } finally {Math.random=original;}
  }
  for(const reward of ['cash','ammo',...Object.keys(d.AFFIXES)])for(const lifetime of [.05,20])for(const altitude of [0,25,25.001]) {
    const actors=[1,2].map(id=>({id,pid:id,hero:true,ch:'t05',kind:'robot',side:id===1?'STEEL':'SWARM',x:0,z:0,y:id===1?altitude:0,
      hp:100,dead:false,money:0,buffs:reward in d.AFFIXES?{[reward]:11}:{},ammo:{light:0,heavy:0},reloadUntil:{light:20,heavy:20}}));
    const loot={id:50,x:0,z:0,ttl:lifetime,...(reward==='cash'?{v:50}:reward==='ammo'?{ammo:true}:{af:reward})};
    const sim=Object.assign(Object.create(template),{t:10,events:[],loots:[loot],_fires:[],curWeatherDyn:null,_allBodies:function*(){yield*actors;}});
    sim._tickHazards(.125);
    scenePickups.push({reward,lifetime,altitude,remaining:sim.loots.length,winner:sim.events.find(e=>e.e==='loot')?.pid??0,
      actors:actors.map(actor=>({id:actor.id,money:actor.money,buffs:actor.buffs,ammoCleared:Object.keys(actor.ammo).length===0,reloadCleared:Object.keys(actor.reloadUntil).length===0}))});
  }
  for(const kind of ['robot','morph','drone'])for(const altitude of [0,d.MORPH.GROUND_Y,d.MORPH.GROUND_Y+.001,
    d.UNITS.robot.jump**2/(2*d.AIR.GRAV),d.UNITS.robot.jump**2/(2*d.AIR.GRAV)+.001])for(const cooldown of [0,10,11]) {
    const character=Object.keys(d.CHARACTERS).find(id=>d.CHARACTERS[id].kind===kind);
    const hero={id:1,pid:1,hero:true,kind,ch:character,side:'STEEL',x:0,z:0,y:altitude,hp:100,dead:false,thirdCd:cooldown};
    const targets=[hero,{id:2,kind:'soldier',side:'SWARM',x:12,z:0,hp:100},{id:3,hero:true,kind:'drone',side:'SWARM',x:0,z:0,y:d.GAME.MINES.R+.001,hp:100,dead:false}];
    const hits=[];
    const sim=Object.assign(Object.create(template),{t:10,events:[],heroes:new Map([[1,hero]]),ents:new Map(targets.map(e=>[e.id,e])),mines:[[0,0,6],[0,0,7]],
      _damage:(target,amount,by,pen)=>hits.push({target:target.id,amount,pen})});
    sim._tickMines();
    sceneMines.push({kind,character,altitude,cooldown,hits,remaining:sim.mines.map(([x,z,id])=>({id,x,z:-z})),until:hero.thirdCd,
      mine:sim.events.find(e=>e.mine)?.mid??0});
  }
  for(const kind of ['drone','morph','robot'])for(const altitude of [0,d.GAME.AA_MIN_ALT-.001,d.GAME.AA_MIN_ALT])
    for(const gate of ['open','corridor','cooldown','stealth','noSite','full'])for(const seed of [0,1,3,7,9,42]) {
    const character=Object.keys(d.CHARACTERS).find(id=>d.CHARACTERS[id].kind===kind);
    const hero={id:1,pid:1,hero:true,kind,ch:character,side:'STEEL',x:500,z:gate==='corridor'?0:200,y:altitude,hp:100,dead:false,
      thirdCd:gate==='cooldown'?11:0,stealthUntil:gate==='stealth'?11:0};
    const sites=gate==='noSite'?[]:[{id:50,kind:'aasite',x:500,z:200,hp:d.FIELD.AA_SITE.hp},{id:51,kind:'aasite',x:500,z:200,hp:d.FIELD.AA_SITE.hp}];
    const launched=[];
    const sim=Object.assign(Object.create(template),{t:10,events:[],lanes:[[[0,0],[1400,0]]],_allBodies:function*(){yield hero;},
      ents:new Map(sites.map(e=>[e.id,e])),missiles:gate==='full'?[{amb:true}]:[],_takeMissile:(...args)=>{launched.push(args);return {amb:true};}});
    const result=seeded(()=>{sim._tickAmbush(1);return {until:hero.thirdCd,
      launched:launched.map(([actor,side,target,pid,x,y,z,speed,dmg,pen,r,hp,ttl,range,ambush])=>({actor,side,target,position:[x,y,-z],speed,dmg,pen,r,hp,ttl,range,ambush}))};},seed);
    sceneAmbush.push({kind,character,altitude,gate,seed,draws:result.draws,result:result.value});
  }
  for(const pruned of [false,true]) {
    const actors=[1,2].map(id=>({id,hero:true,side:id===1?'STEEL':'SWARM',x:0,z:0,hp:100,dead:false}));
    const relays=[50,51].map(id=>({id,kind:'relay',x:0,z:0,charge:0}));
    const sim=Object.assign(Object.create(template),{t:10,events:[],visionUntil:{STEEL:0,SWARM:0},_relays:relays,
      ents:new Map(pruned?[]:relays.map(e=>[e.id,e])),_allBodies:function*(){yield*actors;}});
    const steps=[];
    for(const [delta,positions] of [[1,[0,100]],[.25,[0,0]],[.5,[100,0]],[1,[100,100]],[1,[100,0]],[2,[100,0]]]) {
      actors.forEach((actor,index)=>actor.x=positions[index]);sim.t+=delta;sim.events=[];sim._tickRelays(delta);
      steps.push({delta,positions,now:sim.t,vision:sim.visionUntil,relays:sim._relays.map(e=>({id:e.id,charge:e.charge,side:e.chargeSide??''})),
        events:sim.events.map(e=>({side:e.side})),entities:sim.ents.size});
      steps[steps.length-1].vision={...sim.visionUntil};
    }
    sceneRelays.push({pruned,steps});
  }
  return {sceneMath,sceneGeneration,sceneCollapse,sceneLoot,scenePickups,sceneMines,sceneAmbush,sceneRelays};
}
