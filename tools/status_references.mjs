// Execute original authority seams; native fixtures do not calculate their own expected outcomes.
export function statusReferences(d, BattleSim, config, makeRng) {
  const clone = value => structuredClone(value);
  const template = new BattleSim(config);
  const statusKeys = {
    empUntil:'emp_until', stunUntil:'stun_until', slowUntil:'slow_until', slowF:'slow_factor',
    freezeUntil:'freeze_until',
    confUntil:'confuse_until', blindUntil:'blind_until', invUntil:'inv_until',
    supUntil:'sup_until', supF:'sup_factor', unbalUntil:'unbalanced_until',
    stealthUntil:'stealth_until', alphaArm:'alpha_arm_until', alphaX:'alpha_multiplier',
    reflectUntil:'reflect_until', reflectArc:'reflect_arc', reflectRatio:'reflect_ratio',
    phaseUntil:'phase_until', phaseDmg:'phase_damage', phaseCrit:'phase_critical',
    noReloadUntil:'no_reload_until', noHeavyReloadUntil:'no_heavy_reload_until',
    noLightReloadUntil:'no_light_reload_until', rootedUntil:'rooted_until',
    markUntil:'mark_until', spRegenHitUntil:'sp_regen_hit_until',
    shieldDefBoostUntil:'shield_def_boost_until', shieldExpandUntil:'shield_expand_until',
    shieldBashUntil:'shield_bash_until', defJumpUntil:'def_jump_until',
    _psnStacks:'poison_stacks', _sonicStacks:'sonic_stacks', _staggerStacks:'stagger_stacks',
    _elemBuildup:'element_buildup', _elemLastHit:'element_last_hit',
  };
  const hero = (character, id=1, side='STEEL', x=0, z=0) => {
    const ch=d.CHARACTERS[character];
    return {id,pid:id,hero:true,ch:character,kind:ch.kind,side,x,z,y:0,ay:0,ry:0,
      hp:200,maxHp:1000,sp:30,maxSp:500,mp:100000,maxMp:100000,armor:d.heroArmor(character),
      dead:false,respawnAt:0,mods:[],buffs:{},abil:{light:1,heavy:1,def:1,atk:1},
      upg:{lw:0,hw:0,def:0,atk:0,hp:0,ar:0,sp:0,ch:0},ammo:{light:1,heavy:1},
      reloadUntil:{light:25,heavy:25},fireAt:{},acd:{},achg:{},money:100,kn:0,
      _spd:0,wet:0,nd:0};
  };
  const state = h => ({id:h.id,hp:h.hp,shield:h.sp,power:h.mp,dead:!!h.dead,defending:!!h.defending,
    respawn_at:h.respawnAt||0,damaged_at:h.lastHitAt??-100,
    buffs:(h.mods||[]).map(m=>({key:m.k,value:m.m,until:m.until,break_on_hit:!!m.brk})),
    status:Object.fromEntries(Object.entries(statusKeys).filter(([source])=>h[source]!=null).map(([source,key])=>[key,clone(h[source])])),
    bleed:h.bleed?{dps:h.bleed.dps,until:h.bleed.until,pen:h.bleed.pen,peer:h.bleed.pid||0}:null,
    aura:h.healAura?{until:h.healAura.until,radius:h.healAura.r,hps:h.healAura.hps,sp_hps:h.healAura.spHps,side:h.healAura.side,cleanse:!!h.healAura.cleanse}:null,
    ammo:clone(h.ammo||{}),reload_at:Object.fromEntries(Object.entries(h.reloadUntil||{}).filter(([,v])=>v>0))});
  const actorInput = h => ({character:h.ch||'',kind:h.kind,id:h.id,side:h.side,position:[h.x,h.y||0,-h.z],
    hp:h.hp,max_hp:h.maxHp,shield:h.sp,max_shield:h.maxSp,power:h.mp,max_power:h.maxMp,
    armor:h.armor,dead:h.dead,respawn_at:h.respawnAt,...(h._spd==null?{}:{velocity:[h._spd,0,0]}),
    absolute_eye:h.ay,relative_altitude:h.y,upgrades:clone(h.upg),
    ...state(h)});
  const context = actors => {
    // Preserve original methods/configuration without rebuilding unrelated scenery for each case.
    const sim=Object.create(template);
    sim.heroes=new Map(actors.filter(h=>h.hero).map(h=>[h.pid,h]));
    sim.ents=new Map(actors.map(h=>[h.id,h]));
    sim.events=[]; sim.t=10; sim.over=false;
    sim.visionUntil={STEEL:0,SWARM:0};
    // Climate is covered separately; these cases isolate status settlement and its RNG stream.
    sim.curWeatherDyn=null;sim.curWeatherVec={fog:0};sim.weatherSurface=null;
    sim._weatherAccuracyPenalty=()=>0;
    return sim;
  };
  const seeded = (seed, callback) => {
    const previous=Math.random, random=makeRng(seed);
    let draws=0;
    Math.random=()=>{draws++;return random();};
    try {return {value:callback(),draws};} finally {Math.random=previous;}
  };
  const statusMath=[];
  const sim=context([]);
  for (const gap of [-200,-78,-40,-26,0,26,26.01,40,78,200]) {
    const attacker={hero:true,ay:gap},target={hero:true,ay:0};
    const critical=sim._altCrit(attacker,target);
    statusMath.push({type:'altitude',gap,suppression:d.highSupF(gap),rate:critical.rate,damage:critical.dmg});
  }
  for (const dodge of [0,.2,.35,.95,1]) for (const suppression of [0,.6,1]) for (const unbalanced of [false,true]) for (const weather of [0,.1,.2]) {
    statusMath.push({type:'miss',dodge,suppression,unbalanced,weather,
      result:d.weatherMissP(d.unbalMissP(d.highSupMissP(dodge,suppression),unbalanced),weather)});
  }
  for (const kind of ['robot','drone','morph']) for (const blast of [false,true]) for (const boosted of [false,true]) for (const slot of [null,'light','heavy']) {
    statusMath.push({type:'shield',kind,blast,boosted,slot:slot||'',result:d.shieldDefKindFactor(kind,blast,boosted,slot)});
  }
  for (const character of Object.keys(d.CHARACTERS)) for (let level=1;level<=4;level++) for (const light of [1,4]) for (const heavy of [1,4]) {
    statusMath.push({type:'selfBoost',character,level,light,heavy,result:d.selfAtkBoost(character,level,{light,heavy})});
  }
  statusMath.push({type:'evasionFloor',result:d.evasionMinSpeed()});
  const statusCritical=[];
  for(const gap of [-78,-26,0,26,40,78]) for(const chance of [0,.3,1]) for(const forced of [false,true]) for(const unbalanced of [false,true]) {
    const attacker=hero('s01'),target=hero('t05',2,'SWARM');
    attacker.ay=gap;attacker.phaseCrit=forced;
    if(unbalanced)attacker.unbalUntil=11;
    const s=context([attacker,target]),definition={crit:chance,critX:1.8,vs:{}};
    const inputs=[attacker,target].map(actorInput);
    const {value,draws}=seeded(42,()=>s._rollCrit(attacker,definition,100,target));
    statusCritical.push({inputs,definition,now:s.t,result:value,forced:!!attacker.phaseCrit,draws,
      report:s.events.find(event=>event.e==='crit')?.v??null});
  }
  const statusDodge=[];
  for (const character of Object.keys(d.CHARACTERS)) for (const altitude of [0,d.GAME.AA_MIN_ALT,78]) for (const speed of [0,d.EVASION.MOVING_SPD-0.001,d.EVASION.MOVING_SPD,50]) for (const mode of ['plain','evade','suppressed','perfect']) {
    const target=hero(character,2,'SWARM'), attacker=hero('s01');
    target.y=altitude;target.ay=altitude;target._spd=speed;
    if(mode==='evade') target.mods.push({k:'evade',m:.18,until:20});
    if(mode==='perfect') target.mods.push({k:'dodge',m:1,until:20});
    if(mode==='suppressed') {target.supUntil=11;target.supF=.8;}
    const s=context([attacker,target]);
    statusDodge.push({target:actorInput(target),attacker:actorInput(attacker),now:s.t,result:s._dodgeP(target,attacker)});
  }
  const statusElements=[];
  for (const element of ['physical','shock','impact','shockwave','poison','sonic','fire','frost']) for (const slot of ['light','heavy']) for (const mode of ['plain','immune','invulnerable','phase']) {
    const target=hero('t05',2,'SWARM'),attacker=hero('s01');
    if(mode==='immune')target.mods.push({k:'ccImm',m:1,until:30});
    if(mode==='invulnerable')target.invUntil=30;
    if(mode==='phase')target.phaseUntil=30;
    const definition={id:slot,elem:element,rate:7,dmg:100,pen:12,elemBuildup:25,emp:.4};
    const s=context([attacker,target]),input=actorInput(target),steps=[];
    const {draws}=seeded(42,()=>{
      for(let index=0;index<8;index++) {
        s.t=10+index*.1;s._applyHitEmp(attacker,definition,target);s._applyHitElem(attacker,definition,target);
        steps.push({now:s.t,state:state(target)});
      }
      for(const [now,dt] of [[13.2,.1],[13.3,.1],[15,1],[20,1]]) {
        s.t=now;s._tickElemBuildup(dt);steps.push({now,delta:dt,state:state(target)});
      }
    });
    statusElements.push({definition,attacker:actorInput(attacker),target:input,steps,draws});
  }
  const statusCharges=[];
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['def','atk']) for(let level=1;level<=4;level++) for (const deadlines of [[],[10],[9,11],[10,12],[12,14,16]]) {
    const h=hero(character);h.abil[slot]=level;h.acd[slot]=12;
    h.achg[slot]={max:1,rechargeAt:[...deadlines]};
    const s=context([h]),ready=s._readyCharges(h,slot);
    statusCharges.push({character,slot,level,now:s.t,deadlines,cooldown:12,ready,
      resultCooldown:h.acd[slot],resultDeadlines:h.achg[slot].rechargeAt});
  }
  const supported=A=>!A.carrier&&!A.support&&['buff','heal','emp','vision','stealth','rally','recon','intercept','reflect','phaseshift','shield_bash','strike'].includes(A.fx)
    &&(!A.add||['haste','leap','dodge','vamp','mark','evade','overdrive','alpha','stun','slow','confuse','bleed','pull','siege'].includes(A.add.fx));
  const statusAbilities=[];
  for(const character of Object.keys(d.CHARACTERS)) for(const slot of ['def','atk']) for(let level=1;level<=4;level++) {
    const A=d.heroAbility(character,slot,level);
    if(!supported(A))continue;
    for(const fraction of [0,.25,1]) for(const once of [false,true]) {
      const actors=[hero(character),hero('s08',2,'STEEL',2,0),hero('s08',3,'STEEL',10000,0),hero('t05',4,'SWARM',3,0)];
      const h=actors[0];h.abil.atk=level;h.upg.atk=level-1;
      h.abil.light=4;h.upg.lw=3;h.abil.heavy=2;h.upg.hw=1;
      if(A.fx==='rally') {actors[1].hp=0;actors[1].dead=true;actors[1].respawnAt=50;}
      const s=context(actors),inputs=actors.map(actorInput),hits=[],blasts=[],cc=[];
      s._damage=(target,amount,by,pen)=>hits.push({target:target.id,amount,pen});
      s._blast=(by,definition,x,z,y,lev)=>blasts.push({definition,point:[x,y,-z],level:lev});
      s._applyCC=(by,added,x,z,radius)=>cc.push({added,point:[x,0,-z],radius});
      const {draws}=seeded(42,()=>s._castEffect(h,A,0,0,fraction,null,once));
      statusAbilities.push({character,slot,level,fraction,once,now:s.t,actors:inputs,
        result:actors.map(state),vision:s.visionUntil,hits,blasts,cc,draws});
    }
  }
  const statusInterruptions=[];
  for(const character of Object.keys(d.CHARACTERS)) for(let level=1;level<=4;level++) {
    const A=d.heroAbility(character,'def',level);
    for(const elapsed of [-.1,0,A.castTime*.25,A.castTime*.5,A.castTime,A.castTime+.1]) {
      const h=hero(character),s=context([h]);
      h.cast={start:10,dur:A.castTime,A,x:0,z:0,lvl:level};h.castLockUntil=40;s.t=10+elapsed;
      let fraction=null;s._castEffect=(by,definition,x,z,value)=>{fraction=value;};
      s._interruptCast(h);
      statusInterruptions.push({character,level,now:s.t,start:10,duration:A.castTime,fraction,cast:h.cast,lock:h.castLockUntil});
    }
  }
  const statusSettlement=[];
  for(const character of Object.keys(d.CHARACTERS)) for(const mode of ['plain','front','rear','expanded','boosted','blast','reflect','freeze','invulnerable','phase','interrupt','unbalanced']) {
    const attacker=hero('s04'),target=hero(character,2,'SWARM');
    attacker.z=mode==='rear'?-50:50;target.hp=800;
    attacker.mods=[{k:'dmg',m:1.8,until:20},{k:'vamp',m:.2,until:20}];
    target.mods=[{k:'dmgTaken',m:.75,until:20}];
    target.defending=['front','rear','expanded','boosted','blast','unbalanced'].includes(mode);
    if(mode==='expanded') {attacker.x=50;attacker.z=0;target.shieldExpandUntil=20;}
    if(mode==='boosted')target.shieldDefBoostUntil=20;
    if(mode==='reflect')target.reflectUntil=20;
    if(mode==='freeze')target.freezeUntil=20;
    if(mode==='invulnerable')target.invUntil=20;
    if(mode==='phase')target.phaseUntil=20;
    if(mode==='unbalanced') {target.y=78;target.ay=78;}
    const definition={dmg:100,pen:10,vsSp:1.4,vsHp:.8,spPierce:.1,vs:{armor:1.2,air:.8},type:'gun',elem:'physical'};
    const sourceContext=mode==='blast'?{blast:[0,2,5]}:{origin:[attacker.x,attacker.z]};
    const nativeContext=mode==='blast'?{blast:[0,0,-2],radius:5}:{origin:[attacker.x,0,-attacker.z]};
    const s=context([attacker,target]);
    if(mode==='interrupt') {
      // Unsupported field production is recorded separately; use an authored heal cast here.
      const heal=d.heroAbility('s08','def',1);
      target.cast={start:s.t-heal.castTime*.5,dur:heal.castTime,A:heal,x:target.x,z:target.z,lvl:1};
      target.castLockUntil=20;
    }
    const input=[attacker,target].map(actorInput),cast=target.cast?clone(target.cast):null;
    const {draws}=seeded(42,()=>s._damage(target,s._heroDmg(attacker,definition,target.kind),attacker,definition.pen,0,definition,sourceContext));
    statusSettlement.push({character,mode,definition,context:nativeContext,actors:input,cast,
      result:[attacker,target].map(state),damage_out:attacker.dmgOut||0,assisted:!!target.asst?.[attacker.pid],draws});
  }
  const statusPhase=[];
  for(const damage of [0,12.5,50]) for(const dead of [false,true]) {
    const h=hero('m08');h.phaseUntil=10.5;h.phaseDmg=damage;
    if(dead){h.hp=0;h.dead=true;}
    const s=context([h]),input=actorInput(h),steps=[];
    s._blast=(by,definition,x,z,y,lev)=>blasts.push({definition,point:[x,y,-z],level:lev});
    s._applyCC=(by,added,x,z,radius)=>cc.push({added,point:[x,0,-z],radius});
    let blasts=[],cc=[];
    for(const now of [10.499,10.5,10.6]) {
      s.t=now;s._tickPhaseShift(1/60);
      steps.push({now,state:state(h),blasts:blasts.splice(0),cc:cc.splice(0)});
    }
    statusPhase.push({input,steps});
  }
  const tickSource=BattleSim.prototype.tick.toString();
  const bashStart=tickSource.indexOf('    for (const h of this.heroes.values()) {',tickSource.indexOf('if (hh.dead) this._promote(sq)'));
  const bashEnd=tickSource.indexOf('    for (const e of [...this.ents.values()]) {',bashStart);
  const npcStart=tickSource.indexOf('        if (e.cd === 0 && !u.guns');
  const npcEnd=tickSource.indexOf('        continue;',npcStart);
  if(bashStart<0||bashEnd<bashStart||npcStart<0||npcEnd<npcStart)throw new Error('Original shield bash / NPC fire tick seam missing');
  const bash=new Function('dt',tickSource.slice(bashStart,bashEnd));
  const npcScope={...d};
  const npcFire=new Function(...Object.keys(npcScope),'e','u','target',tickSource.slice(npcStart,npcEnd));
  const statusBash=[];
  for(const defending of [false,true]) for(const shield of [0,30]) for(const expiry of [10,11]) {
    const h=hero('s04');h.defending=defending;h.sp=shield;h.shieldBashUntil=expiry;
    const actors=[h,...[[0,3],[0,5],[0,5.01],[4,3],[0,-3],[0,0]].map(([x,z],index)=>hero('t05',index+2,'SWARM',x,z))];
    const s=context(actors),inputs=actors.map(actorInput),hits=[];
    s._damage=(target,amount,by,pen)=>hits.push({target:target.id,amount,pen});
    s._placeSolid=(target,x,z)=>{target.x=x;target.z=z;};
    bash.call(s,1/60);
    statusBash.push({inputs,now:s.t,delta:1/60,hits,result:actors.map(h=>({id:h.id,position:[h.x,h.y,-h.z]}))});
  }
  const statusNpcFire=[];
  for(const kind of ['soldier','rocketeer','howitzer','heli','tank','apc','tower']) for(const mode of ['plain','moving','emp']) {
    const unit=d.UNITS[kind],e={id:1,kind,side:'STEEL',x:0,z:0,y:0,hp:unit.hp,maxHp:unit.hp,sp:0,maxSp:0,mp:0,maxMp:0,cd:0};
    if(mode==='emp')e.empUntil=11;
    const target=hero('s09',2,'SWARM',0,10);target._spd=mode==='moving'?50:0;
    const s=context([e,target]),hits=[],blasts=[];
    s.curWeatherDyn=null;s.weatherSurface=null;s._weatherAccuracyPenalty=()=>0;s._unitLev=()=>0;
    s._damage=(target,amount,by,pen)=>hits.push({target:target.id,amount,pen});
    s._blast=(by,definition,x,z,y,lev,friendly,npc_damage)=>blasts.push({definition,point:[x,y,-z],level:lev,npc_damage});
    const {draws}=seeded(42,()=>npcFire.call(s,...Object.values(npcScope),e,unit,target));
    statusNpcFire.push({kind,mode,inputs:[actorInput(e),actorInput(target)],now:s.t,hits,blasts,draws,shot:s.events.some(event=>event.e==='shot')});
  }
  const statusFloors=[];
  for(const kind of ['hero','boss','npc']) for(const hp of [.25,.5,1,5,10,25,100])
  for(const shield of kind==='npc'?[0]:[0,30]) for(const floor of [0,d.SIEGE.BLD_HP_FLOOR,10]) for(const siegeFloor of [0,d.SIEGE.BLD_HP_FLOOR])
  for(const amount of [.1,5,25,250]) for(const definition of [null,{vsHp:0},{spPierce:.5,vsSp:1.4,vsHp:.8}]) {
    const attacker=hero('t05'),target=hero('t05',2,'SWARM');
    attacker.mods.push({k:'vamp',m:.2,until:20});
    target.hp=hp;target.sp=shield;target.armor=0;
    if(kind==='npc'){target.hero=false;target.kind='soldier';target.ch='';}
    if(kind==='boss')target.sq={boss:true,bossSeg:0};
    const s=context([attacker,target]),inputs=[attacker,target].map(actorInput),order=[];
    s.siegeHpFloor=()=>siegeFloor;
    s._kill=t=>{order.push('kill');t.hp=0;t.dead=true;};
    s._bossSync=()=>order.push('boss_sync');
    const {draws}=seeded(42,()=>s._damage(target,amount,attacker,0,floor,definition));
    statusFloors.push({kind,inputs,floor,siegeFloor,amount,definition,draws,
      result:{hp:target.hp,shield:target.sp,dead:!!target.dead,attacker_hp:attacker.hp,
        damage_out:attacker.dmgOut||0,assisted:!!target.asst?.[attacker.pid],focus:attacker.lastHitTargetId===target.id,order}});
  }
  const statusHealAuras=[];
  const auraLevels=[1,2,3,4,...[1,19,20,21,39,100].map(value=>d.superCombatLvl(value))];
  for(const level of auraLevels)for(const fraction of [0,.25,1])for(const bossStage of Array.from({length:d.bossSegN()},(_,index)=>index))
  for(const casterBoss of [false,true])for(const scenario of ['expire','recast','owner_dead','zero_hp_target']) {
    const h=hero('s08'),ally=hero('t05',2,'STEEL',2,0),boss=hero('t05',3,'STEEL',3,0);
    h.abil.def=level;h.pid=42;
    if(casterBoss)h.sq={boss:true,bossSeg:bossStage,bodies:[h]};
    boss.sq={boss:true,bossSeg:bossStage,bodies:[boss]};
    ally.mods.push({k:'healAmp',m:1.5,until:100});
    const npc=(id,x,extra={})=>({id,kind:'soldier',side:'STEEL',x,z:0,y:0,hp:d.UNITS.soldier.hp*.4,
      maxHp:d.UNITS.soldier.hp,sp:0,maxSp:0,mp:0,maxMp:0,armor:d.UNITS.soldier.armor,mods:[],buffs:{},dead:false,...extra});
    const A=d.heroAbility(h.ch,'def',level),dead=hero('t05',9,'STEEL',2,0);dead.hp=0;dead.dead=true;
    const actors=[h,ally,boss,npc(4,5),npc(5,6,{neutral:true}),hero('t05',6,'SWARM',7,0),
      npc(7,A.r+1,{r:1}),npc(8,A.r+1.01,{r:1}),dead];
    const s=context(actors);
    // Use the active t05 clone producer; clones remain entity-only aura targets.
    s._castEffect(ally,d.heroAbility(ally.ch,'atk',1),ally.x,ally.z,1,null,true);
    s.events=[];
    const roster=[...s.ents.values()],ids=new Map(roster.map((e,index)=>[e,index+1]));
    const inputs=roster.map(e=>({...actorInput(e),id:ids.get(e),source_id:e.id,hero:!!e.hero,clone:!!e.isClone,
      peer:e.pid??0,effect_radius:e.r||0,boss:!!e.sq?.boss,boss_segment:e.sq?.bossSeg||0,neutral:!!e.neutral}));
    const reports=()=>s.events.splice(0).filter(e=>['heal_aoe','heal_aura_start','heal_aura_end'].includes(e.e)).map(e=>({
      type:e.e,actor:ids.get(s.heroes.get(e.pid)),peer:e.pid,side:e.side,radius:e.r??null,duration:e.dur??null,
      position:e.x==null?null:[e.x,0,-e.z]}));
    const snapshot=()=>({actors:roster.map(e=>({id:ids.get(e),hp:e.hp,shield:e.sp||0,dead:!!e.dead})),
      active:!!h.healAura,aura:state(h).aura,events:reports()});
    s._castEffect(h,A,0,0,fraction,null,true);
    const initial=snapshot(),duration=(A.dur||6)*fraction,frames=[];
    const ages=duration>0?[0,.125,.5,duration-.001,duration,duration+.125,duration+.25]:[0,.125,.25];
    let previous=0;
    const {draws}=seeded(42,()=>{
      for(const [index,age]of ages.entries()) {
        s.t=10+age;
        const recast=scenario==='recast'&&index===1,die=scenario==='owner_dead'&&index===1;
        const zeroHpTarget=scenario==='zero_hp_target'&&index===1;
        if(recast)s._castEffect(h,A,0,0,fraction,null,true);
        if(die){h.hp=0;h.dead=true;}
        if(zeroHpTarget)ally.hp=0;
        const delta=age-previous;s._tickHealAuras(delta);
        frames.push({now:s.t,delta,recast,die,zeroHpTarget,result:snapshot()});previous=age;
      }
    });
    statusHealAuras.push({character:h.ch,level,fraction,inputs,initial,frames,draws});
  }
  return {statusMath,statusCritical,statusDodge,statusElements,statusCharges,statusAbilities,statusInterruptions,statusSettlement,statusPhase,statusBash,statusNpcFire,statusFloors,statusHealAuras};
}
