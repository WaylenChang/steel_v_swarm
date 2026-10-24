import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {carrierControllerReferences} from './carrier_controller_references.mjs';

// Execute the active room bot/tick seam and BattleSim.tick. External model,
// climate, pathfinding and NPC weapon producers are traced at their boundaries;
// recovery, cast admission/completion, fire and heal auras remain original code.
export async function tickReferences(d, BattleSim, config, makeRng, source) {
  const rooms = (await readFile(join(source, 'server/rooms.js'), 'utf8')).replace(/\r\n/g, '\n');
  const seam = /for \(const brain of room\.botBrains\) brain\.update\(dt\);\s*room\.battle\.tick\(dt\);/.exec(rooms);
  if (!seam) throw new Error('Original room bot-before-battle tick seam missing');
  const roomStep = new Function('room', 'dt', seam[0]);
  const template = new BattleSim(config), tick = d.GAME.TICK_MS / 1000;
  const schedules = [Array(64).fill(tick), Array(512).fill(tick / 8), Array(480).fill(1 / 60), Array(16).fill(tick * 4),
    Array.from({length:16}, () => [.03,.07,.15,.25]).flat()];
  const simulationFrames = [];
  for (const hp of [200,999]) for (const powerGap of [-1,0]) for (const fighting of [false,true])
  for (const fireTtl of [null,tick]) for (const schedule of schedules) {
    const ability = d.heroAbility('s08', 'def', 1);
    const hero = (id, pid, ch) => ({id,pid,ch,hero:true,kind:d.CHARACTERS[ch].kind,side:'STEEL',
      x:0,z:0,y:0,ay:0,ry:0,hp,maxHp:1000,sp:499,maxSp:500,mp:Math.round(ability.mp)+powerGap,maxMp:100000,
      mpRegen:d.UNITS[d.CHARACTERS[ch].kind].mpRegen,armor:d.heroArmor(ch),dead:false,wet:0,
      mods:[],buffs:{},abil:{def:1,atk:1,light:1,heavy:1},upg:{lw:0,hw:0,def:0,atk:0,hp:0,ar:0,sp:0,ch:0},
      achg:{},acd:{},ammo:{light:1,heavy:1},reloadUntil:{},lastHitAt:fighting?10:-99,kn:0});
    const owner=hero(1,42,'s08'),ally=hero(2,7,'t05');
    const npc={id:3,kind:'soldier',side:'STEEL',x:80,z:0,hp:100,maxHp:100,cd:999,
      lane:0,wv:1,prog:40,_eng:true};
    const actors=[owner,ally,npc];
    const s=Object.assign(Object.create(template),{t:10,over:false,_tickN:0,events:[],
      ents:new Map(actors.map(e=>[e.id,e])),heroes:new Map([[42,owner],[7,ally]]),
      squads:new Map(),missiles:[],loots:[],_tgGrid:null,_pushBuckets:null,
      _fires:[{id:500,kind:'fire',x:0,z:0,sc:1,ttl:fireTtl}],
      nextWaveAt:10+tick,nextAirdropAt:10+tick,wave:0,curWeatherDyn:null,weatherSurface:null});
    for(const h of [owner,ally]) {h.sq={pid:h.pid,ps:h,bodies:[h],lockAt:10,lock:0};s.squads.set(h.pid,h.sq);}
    const traces=[];
    const phase=(name,delta=0)=>traces.push({phase:name,now:s.t,delta});
    const wrap=(method,name,real=false)=>{const original=BattleSim.prototype[method];
      if(typeof original!=='function')throw new Error('Missing original tick producer '+method);
      s[method]=function(...args){phase(name,args[0]??0);if(real)return original.apply(this,args);};};
    s._tickWeather=delta=>{phase('weather',delta);s.curWeatherDyn=null;};
    for(const [method,name,real]of [['_spawnWave','wave'],['_spawnAirdropWave','airdrop_wave'],
      ['_tickCasts','casts',true],['_tickDecoys','carriers'],['_tickCivilians','civilians'],['_tickMines','mines'],
      ['_tickAmbush','ambush'],['_tickRelays','relays'],['_tickHazards','hazards',true],['_tickAirdrops','airdrops'],
      ['_tickCamps','camps'],['_tickHealAuras','auras',true],['_tickClones','clones'],['_tickCubicSlabs','slabs'],
      ['_tickFogs','fogs'],['_tickSummons','summons'],['_tickPhaseShift','phase'],['_tickDecoyBeacons','holograms'],
      ['_tickElemBuildup','elements'],['_buildTickIndex','index'],['_tickMissiles','missiles']])wrap(method,name,real);
    // These unsupported/empty producers do not supply mechanics to this seam.
    for(const method of ['_tickSquads','_tickKamis','_tickHypers','_tickStorms','_tickBoomerangs','_tickFirePillars',
      '_tickQuakes','_tickTrees','_tickDarkMoons','_tickThermiteMines','_tickEntangle','_tickNanites','_tickSingularity',
      '_tickCoverStealth','_advance','_rebuildAvoidZones'])s[method]=()=>{};
    s._waveAnchors=()=>{phase('anchors');return BattleSim.prototype._waveAnchors.call(s);};
    s._acquireCached=()=>{phase('npc');return s._tickN%2?ally:null;};
    s._trailPush=()=>phase('trail');
    const brain={update:delta=>{phase('bot',delta);s.heroCast(owner.pid,'def',owner.x,owner.z);}};
    const inputs=actors.map(e=>({id:e.id,peer:e.pid??0,character:e.ch||'',kind:e.kind,side:e.side,
      position:[e.x,0,-e.z],hp:e.hp,max_hp:e.maxHp,shield:e.sp||0,max_shield:e.maxSp||0,
      power:e.mp||0,max_power:e.maxMp||0,armor:e.armor||0,damaged_at:e.lastHitAt??-99}));
    s._castEffect(owner,ability,owner.x,owner.z,1,null,true);s.events=[];
    const originalRandom=Math.random,random=makeRng(42);let draws=0,accumulator=0;
    Math.random=()=>{draws++;return random();};
    const frames=[];
    try {
      for(const delta of schedule){
        accumulator+=delta;
        while(accumulator+1e-9>=tick){accumulator=Math.max(0,accumulator-tick);roomStep({botBrains:[brain],battle:s},tick);}
        frames.push({delta,result:{clock:s.t,trace:traces.splice(0),
          actors:[owner,ally].map(e=>({id:e.id,hp:e.hp,shield:e.sp,power:e.mp,
            cast_until:e.cast?e.cast.start+e.cast.dur:0,aura_until:e.healAura?.until??0,cooldown:e.acd.def||0})),
          anchors:Object.fromEntries(s._anchors||[]),engaged:!!npc._eng,
          events:s.events.splice(0).filter(e=>['cast_start','cast','heal_aoe','heal_aura_start','heal_aura_end'].includes(e.e))
            .map(e=>({type:e.e,peer:e.pid}))}});
      }
    } finally {Math.random=originalRandom;}
    simulationFrames.push({inputs,fireTtl,bases:Object.fromEntries(Object.entries(s.basePos).map(([side,p])=>[side,[p[0],0,-p[1]]])),frames,draws});
  }
  return {simulationFrames,...carrierControllerReferences(d,BattleSim,config,makeRng)};
}
