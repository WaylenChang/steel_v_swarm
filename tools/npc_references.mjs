import {readFile} from 'node:fs/promises';
import {join} from 'node:path';

// Original target gates/selection/cache and creep settlement supply every expected value.
export async function npcReferences(d, BattleSim, config, source) {
  const text=await readFile(join(source,'server/sim.js'),'utf8');
  const rescan=/const TG_RESCAN\s*=\s*(\d+)/.exec(text),cell=/const TG_CELL\s*=\s*(\d+)/.exec(text);
  if(!rescan||!cell)throw new Error('Source NPC targeting constants missing');
  const rules={rescan:Number(rescan[1]),cell:Number(cell[1]),candidate_range:d.altRangeMax()};
  const template=new BattleSim(config);
  const actor=(id,kind,side,x=0,z=0,y=0)=>({id,kind,side,x:Math.fround(x),z:Math.fround(z),y,hp:10000,maxHp:10000,armor:0,mods:[],buffs:{}});
  const context=actors=>Object.assign(Object.create(template),{t:10,_tickN:0,_tgSeq:0,_tgGrid:null,_losGrid:null,
    ents:new Map(actors.map(e=>[e.id,e])),heroes:new Map(actors.filter(e=>e.hero).map(e=>[e.pid,e])),
    curWeatherVec:{fog:0},curWeatherDyn:null,weatherSurface:null,events:[],over:false,stats:structuredClone(template.stats)});
  const spec=(s,e)=>({kind:e.kind,side:e.side,hero:!!e.hero,hp:e.hp,dead:!!e.dead,neutral:!!e.neutral,
    garrison:!!e.gar,third:!!e.tp,siege_locked:!!e.locked,stealth:(e.stealthUntil||0)>s.t,blind:(e.blindUntil||0)>s.t,
    altitude:e.y||0,sight_height:s._sightY(e,false),hologram:!!e.isHoloDecoy});
  const npcGates=[];
  for(const kind of ['soldier','rocketeer','howitzer','tower','base'])for(const targetKind of ['robot','drone','heli','hyper','decoy_beacon','tank','tower'])
    for(const altitude of [0,20,80,200])for(const fog of [0,75,90,100])for(const distance of [50,150,250,350]) {
      const observer=actor(1,kind,'STEEL'),target=actor(2,targetKind,'SWARM',distance,0,altitude);
      if(['robot','drone'].includes(targetKind)){target.hero=true;target.pid='2';}
      if(targetKind==='hyper')target.hyper=true;
      if(targetKind==='decoy_beacon')target.isHoloDecoy=true;
      const profile=kind==='base'?{range:d.UNITS.base.guns.range}:d.UNITS[kind],weapon=profile.wid?d.WEAPONS[profile.wid]:null;
      const s=context([observer,target]);s.curWeatherVec.fog=fog;s.siegeLocked=e=>!!e.locked;
      npcGates.push({observer:spec(s,observer),target:spec(s,target),profile,weapon:weapon||{},distance,
        altitude_factor:s._altRange(observer,target,weapon),fog,blocked:s._tgBlockedD(observer,profile,weapon,target,distance)});
    }
  const npcSideGates=[];
  for(const sourceSide of ['STEEL','SWARM','GUER','MILI',d.SUPER_SIDE])for(const targetSide of ['STEEL','SWARM','GUER','MILI',d.SUPER_SIDE])
    for(const flag of ['none','neutral','garrison','locked','stealth','blind','dead']) {
      const observer=actor(1,'tower',sourceSide),target=actor(2,'robot',targetSide,10,0);target.hero=true;target.pid='2';
      observer.tp=d.isThirdSide(sourceSide);target.tp=d.isThirdSide(targetSide);
      if(flag==='blind')observer.blindUntil=20;
      if(flag==='stealth')target.stealthUntil=20;
      if(flag==='dead')target.dead=true;
      if(flag==='neutral')target.neutral=true;
      if(flag==='garrison')target.gar=true;
      if(flag==='locked')target.locked=true;
      const s=context([observer,target]);s.siegeLocked=e=>!!e.locked;
      npcSideGates.push({observer:spec(s,observer),target:spec(s,target),profile:d.UNITS.tower,weapon:{},distance:10,
        altitude_factor:1,fog:0,blocked:s._tgBlockedD(observer,d.UNITS.tower,null,target,10)});
    }
  const npcSelection=[];
  for(const kind of ['soldier','rocketeer','howitzer','heli','tank','apc','tower','base'])for(const grid of [false,true])
    for(const holo of [false,true])for(const blocked of [0,2,3,4])for(const fog of [0,90]) {
      const observer=actor(1,kind,'STEEL'),targets=[actor(2,'robot','SWARM',0,100),actor(3,'tank','SWARM',60,0),actor(4,'decoy_beacon','SWARM',0,120),actor(5,'soldier','SWARM',-60,0)];
      targets[0].hero=true;targets[0].pid='2';targets[2].isHoloDecoy=holo;
      const s=context([observer,...targets]),queries=[];s.curWeatherVec.fog=fog;s._losGrid={};s.siegeLocked=()=>false;
      s._losBlocked=(_x,_z,_y,_tx,_tz,_ty,_e,t)=>{queries.push(t.id);return t.id===blocked;};
      if(grid)s._buildTickIndex();
      const profile=kind==='base'?{range:d.UNITS.base.guns.range}:d.UNITS[kind];
      npcSelection.push({kind,grid,holo,blocked,fog,target:s._acquireTarget(observer,profile)?.id||0,queries,
        actors:targets.map(e=>({id:e.id,...spec(s,e),position:[e.x,e.y,-e.z]}))});
    }
  const npcCache=[];
  for(const hidden of [false,true])for(const dead of [false,true]) {
    const observer=actor(1,'soldier','STEEL'),first=actor(2,'soldier','SWARM',0,40),other=actor(3,'soldier','SWARM',0,80);
    const s=context([observer,first,other]);s._losGrid={};s.siegeLocked=()=>false;s._losBlocked=(_x,_z,_y,_tx,_tz,_ty,_e,t)=>!!t.hidden;
    const steps=[];
    for(let tick=0;tick<12;tick++) {
      s._tickN=tick;s.t=tick*d.GAME.TICK_MS/1000;
      if(tick===1)other.z=10;
      if(tick===5){other.hidden=hidden;if(dead)other.hp=0;}
      const target=s._acquireCached(observer,d.UNITS.soldier);
      steps.push({now:s.t,tick,target:target?.id||0,phase:observer._tgPh,first:[first.x,first.y,-first.z],other:[other.x,other.y,-other.z],other_hp:other.hp,hidden:!!other.hidden});
    }
    npcCache.push({steps});
  }
  const creepMath=[];
  for(const level of [-1,0,.9,1,3,10,99,100,101])for(const armor of [0,12,30])for(const penetration of [0,10,50]) {
    const multiplier=d.creepUpgMul(level);
    creepMath.push({level,armor,penetration,multiplier,taken:d.creepDmgTakenF(multiplier,armor,penetration)});
  }
  const creepSettlement=[];
  for(const heroAttack of [false,true])for(const level of [0,1,10,100])for(const penetration of [0,10,50]) {
    const observer=actor(1,heroAttack?'robot':'soldier','STEEL'),target=actor(2,'tank','SWARM',0,15);
    if(heroAttack){observer.hero=true;observer.pid='1';observer.ch='t05';observer.money=0;observer.kn=0;}
    target.armor=30;target.cu=d.creepUpgMul(level);
    const s=context([observer,target]);s.siegeLocked=()=>false;s.siegeHpFloor=()=>0;s._allyBotDmgF=()=>1;
    s._damage(target,80,observer,penetration,0,{type:'gun'});
    creepSettlement.push({heroAttack,level,penetration,loss:10000-target.hp});
  }
  const creepPurchases=[];
  for(const maxed of [false,true])for(const dead of [false,true])for(const money of [0,d.CREEP_UPG.PRICE])for(const lane of [-1,0,1,2])for(const level of [0,d.CREEP_UPG.MAX]) {
    const h=actor(1,'robot','STEEL');Object.assign(h,{hero:true,pid:'1',ch:'t05',dead,hp:dead?0:10000,money,kn:1000,
      upg:Object.fromEntries(Object.entries(d.ECON.UPGRADES).map(([key,value])=>[key,maxed?value.max:0]))});
    const s=context([h]);s.creepUpg={STEEL:[level,0],SWARM:[0,0]};s.isBoss=()=>false;
    const error=s.buy(h.pid,'creep',lane);
    creepPurchases.push({maxed,dead,money,lane,level,accepted:error==null,balance:h.money,levels:s.creepUpg.STEEL});
  }
  const deadPurchases=[];
  for(const track of ['hp','sp','ar','lw','hw','def','atk','ch'])for(const dead of [false,true]) {
    const h=actor(1,'robot','STEEL');Object.assign(h,{hero:true,pid:'1',ch:'t05',dead,hp:dead?0:400,maxHp:Math.round(d.UNITS.robot.hp*d.CHARACTERS.t05.mods.hp),
      sp:dead?0:80,maxSp:Math.round(d.UNITS.robot.shield*d.CHARACTERS.t05.mods.sp),money:10000,kn:1000,abil:{light:1,heavy:1,def:1,atk:1},
      upg:Object.fromEntries(Object.keys(d.ECON.UPGRADES).map(key=>[key,0])),ammo:{},reloadUntil:{}});
    const s=context([h]);s.isBoss=()=>false;const error=s.buy(h.pid,track);
    deadPurchases.push({track,dead,accepted:error==null,hp:h.hp,max_hp:h.maxHp,shield:h.sp,max_shield:h.maxSp,armor:h.armor,money:h.money,level:h.upg[track]});
  }
  return {rules,fixtures:{npcGates,npcSideGates,npcSelection,npcCache,creepMath,creepSettlement,creepPurchases,deadPurchases}};
}
