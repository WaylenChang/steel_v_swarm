// Offline source oracles for autonomous actors. No native implementation supplies expected values.
export function companionReferences(d, BattleSim, config, makeRng) {
  const template = new BattleSim(config);
  const kinds = ['drone_wingman','assault_rover','heli_squad','main_battle_tank','veteran_squad','carnival_heli'];
  const hero = (character='t05', id=1, side='STEEL', x=0, z=0) => ({id,pid:String(id),ch:character,hero:true,
    kind:d.CHARACTERS[character].kind,side,x,z,y:0,ry:.4,hp:400,maxHp:1000,sp:80,maxSp:500,mp:1000,maxMp:1000,
    armor:12,dead:false,mods:[],buffs:{},abil:{light:1,heavy:1,def:1,atk:1},upg:{},acd:{},achg:{},money:100,kn:0});
  const context = actors => {
    const s=Object.assign(Object.create(template),{t:10,over:false,events:[],_tickN:1,
      ents:new Map(actors.map(a=>[a.id,a])),heroes:new Map(actors.filter(a=>a.hero).map(a=>[a.pid,a])),
      autonomousSummons:[],hologramDecoys:[],stats:structuredClone(template.stats),
      curWeatherDyn:{wind:0,windDir:0,rainAtkMul:1},weatherSurface:{},curWeatherVec:{fog:0}});
    let next=Math.max(0,...actors.map(a=>a.id))+1;
    // Local deterministic identity allocation isolates the original producer from the module-global sequence.
    s._add=e=>{e.id=next++;e.maxHp=e.hp;e.cd=0;s.ents.set(e.id,e);return e;};
    s._placeSolid=(e,x,z)=>{e.x=x;e.z=z;};
    return s;
  };
  const seeded = callback => {
    const original=Math.random,random=makeRng(42);let draws=0;
    Math.random=()=>{draws++;return random();};
    try{return {value:callback(),draws};}finally{Math.random=original;}
  };
  const state = e => ({position:[e.x,e.y||0,-e.z],yaw:e.ry||0,hp:e.hp,max_hp:e.maxHp,shield:e.sp||0,max_shield:e.maxSp||0,
    armor:e.armor||0,speed:e.speed||0,cd:e.cd||0,range:e.range??null,rate:e.rate??null,sight:e.sight??null,
    damage:e.dmg??null,wid:e.wid??null,offset:e.offset?[e.offset.x,-e.offset.z]:null,
    radius:d.hitR(e),height:d.hitH(e),effect_radius:e.r||0,until:e.until??null});
  const roster = (s,group) => group.filter(e=>s.ents.has(e.id)&&e.hp>0&&!e.dead).map(state);
  const timers = h => ({clones_until:h.clonesUntil??null,no_light_reload_until:h.noLightReloadUntil??null});
  const cloneCharacters=Object.keys(d.CHARACTERS).filter(ch=>d.heroAbility(ch,'atk',1).add?.fx==='clone');
  if(!cloneCharacters.length)throw new Error('Source clone producers missing');
  const companionClones=[];
  for(const character of cloneCharacters)for(const level of [1,2,3,4])for(const fraction of [0,.25,1])for(const yaw of [0,.4,-2]) {
    const h=hero(character),s=context([h]),A=d.heroAbility(character,'atk',level);h.ry=yaw;h.abil.atk=level;
    s._castEffect(h,A,h.x,h.z,fraction,null,true);
    const first={actors:roster(s,h.clones),timers:timers(h)};
    s._castEffect(h,A,h.x,h.z,fraction,null,false);
    const repeated={actors:roster(s,h.clones),timers:timers(h)};
    s._castEffect(h,A,h.x,h.z,fraction,null,true);
    const recast={actors:roster(s,h.clones),timers:timers(h)};
    s._tickClones(.1);
    companionClones.push({character,level,fraction,yaw,first,repeated,recast,after:roster(s,h.clones),afterTimers:timers(h)});
  }
  const companionTargeting=[];
  for(const focus of [0,2,3,4])for(const distance of [50,100,199,200,201,300,300.01])for(const dead of [false,true]) {
    const h=hero(),sight=200,unit={id:8,kind:'main_battle_tank',side:'STEEL',x:0,z:0,hp:100,sight};
    const targets=[hero('s09',2,'SWARM',distance,0),{id:3,kind:'tower',side:'SWARM',x:120,z:0,hp:100},
      {id:4,kind:'soldier',side:'SWARM',x:40,z:0,hp:100},hero('s09',5,'SWARM',distance,0)];
    h.lastHitTargetId=focus;targets[0].dead=dead;if(dead)targets[0].hp=0;
    const s=context([h,...targets]);
    companionTargeting.push({focus,distance,dead,sight,target:s._autoTarget(unit,h)?.id||0});
  }
  const companionSummons=[];
  for(const kind of kinds)for(const level of [1,2,3,4])for(const fraction of [0,.25,1])for(const countOverride of [null,0,3]) {
    const h=hero(),s=context([h]),A={id:'atk',fx:'summon',unit:kind,count:2};h.abil.atk=level;
    const result=seeded(()=>s._spawnAutonomousSummon(h,A,20,-30,fraction,countOverride));
    companionSummons.push({kind,level,fraction,countOverride,draws:result.draws,actors:roster(s,s.autonomousSummons)});
  }
  const companionCombat=[];
  for(const role of ['clone','summon','hologram'])for(const level of [1,4])for(const scenario of ['fire','approach','follow','owner_dead','expiry','tie','swap']) {
    const h=hero(role==='hologram'?'t04':'t05'),enemy=hero('s09',2,'SWARM',0,20),s=context([h,enemy]);
    h.abil.light=level;h.mods=[{k:'dmg',m:1.3,until:30}];
    let group;
    if(role==='clone'){s._spawnClones(h);h.clonesUntil=20;group=h.clones;}
    else if(role==='summon'){seeded(()=>s._spawnAutonomousSummon(h,{id:'atk',unit:'main_battle_tank',count:2},0,0));group=s.autonomousSummons;}
    else {s._castEffect(h,d.heroAbility('t04','def',1),0,0);group=s.hologramDecoys;}
    const initial=group.map(state),weapon=d.heroWeapon(h.ch,'light',level);
    if(scenario==='approach'){enemy.x=(role==='summon'?group[0].range:weapon.range)+80;h.lastHitTargetId=2;}
    if(['follow','owner_dead','expiry','tie','swap'].includes(scenario)){enemy.x=2000;enemy.z=2000;}
    if(scenario==='owner_dead'){h.dead=true;h.hp=0;}
    if(['expiry','tie','swap'].includes(scenario))s.t=100;
    if(scenario==='swap'){group[0].hp=600;group[1].hp=600;group[0].sp=42;group[0].x=30;}
    const hits=[],controls=[];
    s._damage=(target,amount,by,pen=0)=>hits.push({target:target.id,actor:group.indexOf(by),amount,pen});
    s._applyCC=(_owner,added,x,z,r)=>controls.push({effect:added.fx,duration:added.dur,position:[x,0,-z],radius:r});
    const steps=[];
    const result=seeded(()=>{
      for(const delta of [.1,.1,.6]) {
        if(role==='clone')s._tickClones(delta);else if(role==='summon')s._tickSummons(delta);else s._tickDecoyBeacons(delta);
        const shots=s.events.filter(event=>event.e==='shot').map(event=>({actor:group.findIndex(actor=>actor.id===event.id),
          kind:event.kind,pid:event.pid??null,slot:event.slot??null}));
        s.events.length=0;
        steps.push({delta,actors:roster(s,group),owner:{position:[h.x,h.y,-h.z],hp:h.hp,shield:h.sp},hits:hits.splice(0),controls:controls.splice(0),shots});
      }
    });
    companionCombat.push({role,level,scenario,character:h.ch,initial,now:s.t,target:[enemy.x,enemy.y,-enemy.z],draws:result.draws,steps});
  }
  const companionDeaths=[];
  for(const scenario of ['owner_lethal','clone_lethal','summon_kill','clone_kill','clone_interrupt']) {
    const h=hero(),enemy=hero('s09',2,'SWARM',0,15),victim={id:3,kind:'soldier',side:'SWARM',x:10,z:0,y:0,hp:1,maxHp:1,armor:0},s=context([h,enemy,victim]);
    s._spawnClones(h);h.clonesUntil=20;const clones=h.clones.slice();
    clones[0].hp=600;clones[0].sp=42;clones[0].x=30;clones[1].hp=600;
    let caster=null;
    if(scenario==='summon_kill') {
      seeded(()=>s._spawnAutonomousSummon(h,{id:'atk',unit:'main_battle_tank',count:1},0,0));caster=s.autonomousSummons[0];
    }
    if(scenario==='clone_interrupt') {
      h.cast={start:9,dur:2,A:d.heroAbility(h.ch,'def',1),x:0,z:0,lvl:1};
      h.hp=50;h.sp=0;clones[0].sp=0;
    }
    const beforeMoney=h.money;
    if(scenario==='owner_lethal')s._damage(h,10000,enemy,0,0,{type:'gun'});
    else if(scenario==='clone_lethal')s._damage(clones[0],10000,enemy,0,0,{type:'gun'});
    else if(scenario==='clone_interrupt')s._damage(clones[0],1,enemy,0,0,{type:'gun'});
    else s._damage(victim,10,scenario==='summon_kill'?caster:clones[0],0,0,{type:'gun'});
    companionDeaths.push({scenario,clones:roster(s,h.clones),owner:{position:[h.x,h.y,-h.z],hp:h.hp,shield:h.sp,
      earned:h.money-beforeMoney,score:h.kn,focus:h.lastHitTargetId||0,cast:!!h.cast},enemy:{hp:enemy.hp,shield:enemy.sp,money:enemy.money},
      victim:{hp:Math.max(0,victim.hp),assists:Object.keys(victim.asst||{}).map(Number)},targetPresent:s.ents.has(clones[0].id)});
  }
  const companionFrames=[];
  for(const kind of [...kinds,'decoy_beacon'])for(const altitude of [0,2,24,80]) {
    const e={kind,side:'STEEL',x:0,z:0,y:altitude,hp:100},s=context([e]);
    companionFrames.push({kind,altitude,span:s._bodySpan(e),sight:s._sightY(e),eye:s._eyeY(e),target:s._tgtY(e)});
  }
  return {companionClones,companionTargeting,companionSummons,companionCombat,companionDeaths,companionFrames};
}
