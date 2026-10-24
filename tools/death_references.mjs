// Execute original fire, death, respawn and tick predicates. Spatial respawn
// resolution is captured from the original authored lanes; no substitute map.
import {readFileSync} from 'node:fs';
import {join} from 'node:path';

export function deathReferences(d, BattleSim, config, makeRng, source) {
  const template=new BattleSim(config),tick=d.GAME.TICK_MS/1000;
  const characters=[...new Set(['robot','morph','drone'].map(kind=>Object.keys(d.CHARACTERS).find(id=>d.CHARACTERS[id].kind===kind)).concat('s08'))];
  const hero=(id,pid,character,side)=>({id,pid,ch:character,hero:true,kind:d.CHARACTERS[character].kind,side,
    x:0,z:0,y:0,ay:0,ry:0,hp:100,maxHp:100,sp:40,maxSp:80,mp:100000,maxMp:100000,
    mpRegen:d.UNITS[d.CHARACTERS[character].kind].mpRegen,armor:d.heroArmor(character),money:1000,kn:0,
    dead:false,deaths:0,respawnAt:0,lastHitAt:-99,wet:0,mods:[],buffs:{},abil:{light:1,heavy:1,def:1,atk:1},
    upg:{lw:0,hw:0,def:0,atk:0,hp:0,ar:0,sp:0,ch:0},ammo:{light:1,heavy:1},reloadUntil:{light:20},fireAt:{},acd:{},achg:{}});
  const context=actors=>{
    const sim=Object.assign(Object.create(template),{t:10,_tickN:5,over:false,events:[],stats:structuredClone(template.stats),
      ents:new Map(actors.map(e=>[e.id,e])),heroes:new Map(),squads:new Map(),curWeatherDyn:null,
      curWeatherVec:{fog:0},weatherSurface:null,_fires:[],loots:[],missiles:[],_tgGrid:null,_pushBuckets:null,
      nextWaveAt:1e9,nextAirdropAt:1e9});
    for(const h of actors.filter(e=>e.hero)){
      h.sq={pid:h.pid,ps:h,bodies:[h],act:0,lockAt:10,lock:0,deaths:0};
      sim.heroes.set(h.pid,h);sim.squads.set(h.pid,h.sq);
    }
    return sim;
  };
  const input=e=>({id:e.id,peer:e.pid??0,character:e.ch||'',kind:e.kind,side:e.side,position:[e.x,e.y,-e.z],
    hp:e.hp,max_hp:e.maxHp,shield:e.sp||0,max_shield:e.maxSp||0,power:e.mp||0,max_power:e.maxMp||0,
    armor:e.armor||0,money:e.money||0,damaged_at:e.lastHitAt??-99,dead:!!e.dead,affixes:structuredClone(e.buffs||{}),
    ammo:structuredClone(e.ammo||{}),reload_at:structuredClone(e.reloadUntil||{}),upgrades:structuredClone(e.upg||{}),
    aura:e.healAura?{until:e.healAura.until,radius:e.healAura.r,hps:e.healAura.hps,sp_hps:e.healAura.spHps,
      side:e.healAura.side,cleanse:!!e.healAura.cleanse}:null});
  const actorState=(s,e)=>({hp:e.hp,shield:e.sp||0,power:e.mp||0,dead:!!e.dead,deaths:e.deaths||0,
    death_tick:e.deadTick||0,respawn_at:e.dead?e.respawnAt:0,money:e.money||0,score:e.kn||0,damaged_at:e.lastHitAt??-99,
    aura:!!e.healAura,affixes:structuredClone(e.buffs||{}),
    ammo:Object.fromEntries(['light','heavy'].map(slot=>[slot,e.ammo?.[slot]??d.heroWeapon(e.ch,slot,e.abil[slot]).mag]))});
  const reports=s=>s.events.splice(0).filter(e=>['die','penalty','respawn','heal_aura_end'].includes(e.e))
    .map(e=>({type:e.e,peer:e.pid??0,amount:e.e==='penalty'?e.v:null}));
  const seeded=callback=>{const previous=Math.random,random=makeRng(42);let draws=0;Math.random=()=>{draws++;return random();};
    try{return {result:callback(),draws};}finally{Math.random=previous;}};
  const element={id:'heavy',elem:'fire',rate:1,dmg:60,pen:8,elemBuildup:100};
  const deathBurns=[];
  for(const character of characters)for(const hp of [-.1,0,.1,5,100])for(const shield of [0,40])
  for(const amount of [0,.1,25,250,10000])for(const killer of ['none','hero','dead_hero','npc']){
    const victim=hero(1,42,character,'SWARM'),by=hero(2,7,'t05','STEEL');victim.hp=hp;victim.sp=shield;
    if(killer==='npc')Object.assign(by,{hero:false,ch:null,kind:'soldier',pid:null,hp:100});
    if(killer==='dead_hero'){by.hp=0;by.dead=true;}
    const s=context(killer==='none'?[victim]:[victim,by]),inputs=[...s.ents.values()].map(input);
    const {result,draws}=seeded(()=>{
      if(killer!=='none')s._applyHitElem(by,element,victim);
      s.events=[];s._fireBurn(victim,amount);
      return {target:actorState(s,victim),killer_money:killer==='none'?0:by.money,stats:structuredClone(s.stats),events:reports(s)};
    });
    deathBurns.push({character,killer,amount,element,inputs,result,draws});
  }
  const respawnFrames=[];
  for(const character of characters)for(const initialTick of [0,5])for(const offset of [tick*4,tick,0,-tick])
  for(const affix of Object.keys(d.AFFIXES)){
    const victim=hero(1,42,character,'SWARM'),s=context([victim]);s._tickN=initialTick;
    // The active original pickup producer supplies the retained timed affix.
    s.loots=[{x:0,z:0,ttl:60,af:affix}];s._tickHazards(0);s.events=[];
    if(character==='s08')s._castEffect(victim,d.heroAbility(character,'def',1),0,0,1,null,true);
    s.events=[];const inputs=[input(victim)];
    const [x,z]=s._spawnPoint(victim.side,0,0,victim.pid),[dx,dz]=s._spawnAimDir(victim.side,0,x,z);
    const spawn={position:[x,victim.kind==='drone'?d.FLIGHT.HOVER_M:0,-z],yaw:Math.atan2(-dx,dz)};
    // Empty producers isolate the original full-tick respawn predicate and
    // actual respawn cleanup; independent mechanics retain their own fixtures.
    for(const method of ['_tickWeather','_tickSquads','_tickCasts','_tickDecoys','_tickKamis','_tickHypers',
      '_tickCivilians','_tickMines','_tickAmbush','_tickRelays','_tickHazards','_tickAirdrops','_tickCamps',
      '_tickStorms','_tickBoomerangs','_tickFirePillars','_tickQuakes','_tickClones','_tickTrees','_tickDarkMoons',
      '_tickCubicSlabs','_tickFogs','_tickSummons','_tickThermiteMines','_tickEntangle','_tickPhaseShift',
      '_tickDecoyBeacons','_tickNanites','_tickSingularity','_tickElemBuildup','_tickCoverStealth','_buildTickIndex','_tickMissiles'])s[method]=()=>{};
    const {result,draws}=seeded(()=>{
      s._fireBurn(victim,100000);const killed={target:actorState(s,victim),events:reports(s)};
      // Start immediately around the real derived deadline. The original tick
      // counter remains the death counter, exercising the snapshot barrier.
      s.t=victim.respawnAt-offset;const start=s.t,frames=[];
      for(let i=0;i<6;i++){s.tick(tick);frames.push({delta:tick,clock:s.t,tick:s._tickN,target:actorState(s,victim),
        events:reports(s),trail:(victim._trail||[]).filter((_,index)=>index%3===0)});}
      return {start,killed,frames};
    });
    respawnFrames.push({character,initialTick,offset,inputs,spawn,
      bases:Object.fromEntries(Object.entries(s.basePos).map(([side,p])=>[side,[p[0],0,-p[1]]])),...result,draws});
  }
  const rooms=readFileSync(join(source,'server/rooms.js'),'utf8').replace(/\r\n/g,'\n');
  const seam=/for \(const brain of room\.botBrains\) brain\.update\(dt\);\s*room\.battle\.tick\(dt\);/.exec(rooms);
  if(!seam)throw Error('Original room bot/tick seam missing');
  const roomStep=new Function('room','dt',seam[0]),deathOutcomes=[];
  for(const initialTick of [0,5])for(const side of ['STEEL','SWARM']){
    const by=hero(1,42,'t05',side==='STEEL'?'SWARM':'STEEL');
    const base={id:2,kind:'base',side,x:0,z:0,hp:0,maxHp:100};
    const s=context([by,base]);s._tickN=initialTick;let weatherCalls=0;
    const inputs=[by,base].map(input);
    s._tickWeather=()=>weatherCalls++;
    roomStep({battle:s,botBrains:[{update:()=>s._kill(base,by)}]},tick);
    deathOutcomes.push({initialTick,inputs,
      bases:Object.fromEntries(Object.entries(s.basePos).map(([key,p])=>[key,[p[0],0,-p[1]]])),
      result:{clock:s.t,tick:s._tickN,over:s.over,winner:s.winner,weather_calls:weatherCalls}});
  }
  return {deathBurns,respawnFrames,deathOutcomes};
}
