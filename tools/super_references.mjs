import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function superReferences(d, BattleSim, config, source, mulberry32) {
  const { grabMethod } = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = (await readFile(join(source, 'server/sim.js'), 'utf8')).replace(/\r\n/g, '\n');
  const client = (await readFile(join(source, 'public/js/game.js'), 'utf8')).replace(/\r\n/g, '\n');
  const body = grabMethod(text, '_superSpawnPoint');
  const number = (pattern, label, input = body) => {
    const match = pattern.exec(input);
    if (!match) throw new Error('Missing original super seam: ' + label);
    return Number(match[1]);
  };
  const rules = {
    spawn: {attempts:number(/k < (\d+)/,'attempts'),padding:number(/const pad = ([\d.]+)/,'padding'),
      rangeFactor:number(/const clearDist = .*?\* ([\d.]+)/,'range factor'),
      hazardPadding:number(/< hr \+ ([\d.]+)/,'hazard clearance'),separation:number(/>= ([\d.]+)/,'last spawn separation')},
    deathFactor:number(/\* ([\d.]+)\)\)/,'death fraction',grabMethod(text,'_deathPenalty')),
    reserveResend:number(/const RESERVE_RESEND_S = ([\d.]+)/,'reserve resend',client),
    curves:Object.fromEntries(['hp','sp','ar'].map(key=>[key,Array.from({length:d.SUPER_UPG.MAX+1},(_,i)=>d.upgradeCurveMul(key,d.superDefLvl(i)))])),
    charge:Array.from({length:d.SUPER_UPG.MAX+1},(_,i)=>d.chargeF(Math.min(d.ECON.UPGRADES.ch.max,d.superDefLvl(i)))),
  };
  const values = [-10,0,0.9,1,19,19.9,20,21,39,40,99,100,101,999];
  const superMath = values.map(value=>({value,defense:d.superDefLvl(value),combat:d.superCombatLvl(value),scale:d.superScaleF(value)}));
  const state = h => ({level:h.upg.super,hp:h.hp,max_hp:h.maxHp,shield:h.sp,max_shield:h.maxSp,armor:h.armor,
    money:h.money,ammo:structuredClone(h.ammo),reload:structuredClone(h.reloadUntil),radius:d.hitR(h),height:d.hitH(h),
    combat:h.abil.light});
  const superLevels = [], superBuys = [], superDeaths = [], superSummons = [], superCompanions = [], superWeaponGates = [];
  for (const character of Object.keys(d.CHARACTERS)) {
    for (const dead of [false,true]) {
      const sim = new BattleSim({...config,super:true}), h = sim.addHero('SUPER','super',character);
      h.hp = dead ? 0 : Math.floor(h.maxHp*.4); h.sp = dead ? 0 : Math.floor(h.maxSp*.3); h.dead = dead;
      const initial = state(h), steps = [];
      for (const value of [0,1,19,20,21,39,40,99,100,100,20,5,0,-3,100.8]) {
        h.ammo = {light:1,heavy:2}; h.reloadUntil = {light:90,heavy:100}; sim.events = [];
        sim._setSuperLvl(h,value);
        steps.push({value,state:state(h),buys:sim.events.filter(e=>e.e==='buy').length,
          weapons:Object.fromEntries(['light','heavy'].map(slot=>[slot,d.heroWeapon(character,slot,h.abil[slot])])),
          abilities:Object.fromEntries(['def','atk'].map(slot=>[slot,d.heroAbility(character,slot,h.abil[slot])])),
          boost:d.selfAtkBoost(character,h.abil.atk,h.abil),charge:sim._chargeLvl(h)});
      }
      superLevels.push({character,dead,initial,steps});
    }
    for (const setup of [{level:0,money:199.9},{level:0,money:200},{level:99,money:500},{level:100,money:500}]) {
      const sim = new BattleSim({...config,super:true}), h = sim.addHero('SUPER','super',character);
      sim._setSuperLvl(h,setup.level); h.money = setup.money;
      const initial = state(h), success = sim._buySuperUpg(h) === null;
      superBuys.push({character,initial,success,result:state(h)});
    }
    const sim = new BattleSim({...config,super:true}), h = sim.addHero('SUPER','super',character);
    sim._setSuperLvl(h,99); h.money = 453.75; h.hp = 0; h.sp = 0; h.dead = true;
    const initial = state(h); sim.events = []; sim._deathPenalty(h,25);
    superDeaths.push({character,initial,result:state(h),penalty:sim.events.find(e=>e.e==='penalty').v});
    for (const value of [1,20,100]) for (const slot of ['def','atk']) {
      const local = new BattleSim({...config,super:true}), owner = local.addHero('SUPER','super',character);
      local._setSuperLvl(owner,value);
      const ability = d.heroAbility(character,slot,owner.abil[slot]);
      if (ability.fx !== 'summon') continue;
      const original = Math.random, random = mulberry32(88271);
      try { Math.random=random; local._spawnAutonomousSummon(owner,ability,50,-30,.5); }
      finally { Math.random=original; }
      superSummons.push({character,value,slot,definition:ability,seed:88271,fraction:.5,
        result:local.autonomousSummons.map(e=>({hp:e.hp,max_hp:e.maxHp,dmg:e.dmg,armor:e.armor,speed:e.speed,
          position:[e.x,e.y,-e.z],offset:[e.offset.x,-e.offset.z]}))});
    }
    for(const value of [1,7,19,21,39,100]) {
      const local = new BattleSim({...config,super:true}), owner = local.addHero('SUPER','super',character);
      local._setSuperLvl(owner,value); local.t=10; owner.x=0; owner.y=0; owner.z=0; owner.ry=.4;
      const ability=d.heroAbility(character,'atk',owner.abil.atk);
      if(ability.fx!=='decoy_beacon'&&ability.add?.fx!=='clone')continue;
      const initial=state(owner); local._castEffect(owner,ability,0,0,.5,null,true);
      const actors=ability.fx==='decoy_beacon'?local.hologramDecoys:owner.clones;
      superCompanions.push({character,value,definition:ability,initial,result:actors.map(e=>({
        hp:e.hp,max_hp:e.maxHp,shield:e.sp||0,max_shield:e.maxSp||0,armor:e.armor||0,
        position:[e.x,e.y||0,-e.z],radius:d.hitR(e),height:d.hitH(e),
        range:e.range??null,rate:e.rate??null,until:e.until??null}))});
    }
    for(const value of [1,7,19,21,100]) for(const slot of ['light','heavy']) {
      const local=new BattleSim({...config,super:true}), owner=local.addHero('SUPER','super',character);
      local._setSuperLvl(owner,value); local.t=10; local.curWeatherDyn=null; local.weatherSurface=null;
      owner.ammo[slot]=.25;
      const initial=state(owner),power=owner.mp;
      const success=local._gateFire(owner,slot,d.heroWeapon(character,slot,owner.abil[slot]),false);
      superWeaponGates.push({character,value,slot,initial,power,success,ammo:owner.ammo[slot],
        reload:owner.reloadUntil[slot]||0,remainingPower:owner.mp,fireAt:owner.fireAt[slot]||0});
    }
  }
  const superSpawns = [];
  for (const name of ['clear','hazards','fallback','farthest']) {
    const sim = new BattleSim({...config,super:true});
    sim.ents.clear(); sim.basePos={};
    sim.bounds = name === 'farthest' ? {minX:-35,maxX:35,minZ:-35,maxZ:35} : {minX:-600,maxX:600,minZ:-480,maxZ:520};
    sim.lanes = name === 'farthest' ? [] : [[[-600,10],[600,10]]];
    if (name !== 'farthest') sim.basePos={SWARM:[-550,0],STEEL:[550,0]};
    sim.hazBlockers = name === 'hazards' ? [[-220,-250,65],[220,320,80]] : [];
    const blocked = (x,z)=>name === 'fallback' || name === 'hazards' && x < -150 && z > 100;
    sim._terrainBlocked=blocked;
    const original=Math.random, random=mulberry32(47712); let draws=0; const steps=[];
    const initialLast=name === 'farthest' ? [2,3] : null;
    if(initialLast)sim._lastSuperSpawn=initialLast;
    try {
      Math.random=()=>{draws++;return random();};
      for(const pid of ['one','one','two','one']) {
        const point=sim._superSpawnPoint(pid); steps.push({pid,result:[point[0],-point[1]],draws});
      }
    } finally {Math.random=original;}
    superSpawns.push({name,seed:47712,bounds:{...sim.bounds,minZ:-sim.bounds.maxZ,maxZ:-sim.bounds.minZ},
      lanes:sim.lanes.map(lane=>lane.map(([x,z])=>[x,-z])),
      guns:Object.entries(sim.basePos).map(([side,[x,z]])=>({kind:'base',side,x,z:-z})),
      blockers:sim.hazBlockers.map(([x,z,r])=>({x,z:-z,r})),initialLast:initialLast?[initialLast[0],-initialLast[1]]:null,steps});
  }
  return {rules,fixtures:{superMath,superLevels,superBuys,superDeaths,superSummons,superSpawns,superCompanions,superWeaponGates}};
}
