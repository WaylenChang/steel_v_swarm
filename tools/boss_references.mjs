import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// All expected stages, upgrades and unlock deadlines come from the original authority.
export async function bossReferences(d, BattleSim, config, source, gameSource) {
  const text = (await readFile(join(source, 'server/sim.js'), 'utf8')).replace(/\r\n/g, '\n');
  const support = /dist2d\(e.x, e.z, t.x, t.z\) < (\d+)\)/.exec(text);
  const bar = gameSource.slice(gameSource.indexOf('  _updateBossBar(now) {'), gameSource.indexOf('  _updateBossBar(now) {') + 6200);
  const near = /v.z > -([\d.]+)/.exec(bar), view = /Math.abs\(v.x\) > ([\d.]+)/.exec(bar);
  const cover = /hitT < dist - ([\d.]+)/.exec(bar), linger = /_bossLastSeenAt \|\| 0\) > ([\d.]+)/.exec(bar);
  if (!support || !near || !view || !cover || !linger) throw new Error('Missing original siege/BOSS presentation seams');
  const rules = { baseSupportRadius: Number(support[1]), near: Number(near[1]), view: Number(view[1]),
    cover: Number(cover[1]), linger: Number(linger[1]) };
  const clone = x => structuredClone(x);
  const peer = e => e.pid === 'b1' ? -1 : e.pid === 'b99' ? -99 : 1;
  const input = e => ({ id: e.id, peer: e.hero ? peer(e) : 0, hero: !!e.hero, character: e.ch || '',
    kind: e.kind, side: e.side, position: [e.x, e.y || 0, -e.z], is_bot: String(e.pid || '').startsWith('b'),
    hp: e.hp, max_hp: e.maxHp, shield: Math.max(0, e.sp || 0), max_shield: e.maxSp || 0,
    armor: e.armor || 0, money: e.money || 0, score: e.kn || 0, power: e.mp || 0,
    upgrades: clone(e.upg || {}), ammo: clone(e.ammo || {}), reload_at: Object.fromEntries(Object.entries(e.reloadUntil || {}).filter(([,t]) => t > 0)),
    inv_until: e.invUntil || 0, segment: e.sq?.bossSeg || 0, boss: !!e.sq?.boss,
    stage: e.sg ?? -1, dead: !!e.dead, permanent_death: e.respawnAt === Infinity, damage_out: e.dmgOut || 0,
    radius: d.hitR(e), height: d.hitH(e) });
  const state = sim => ({ siege_left: clone(sim._siegeLeft), siege_open: clone(sim._siegeOpen),
    boss_left: clone(sim._bossLeft), talk_until: clone(sim._talkUntil) });
  const context = (side = 'STEEL', size = 3) => {
    const sim = new BattleSim({ ...config, siege: true, defSide: side, teamSize: size });
    sim.t = 10; sim.curWeatherDyn = null;
    sim._botAirSink = () => {}; sim._stampSup = () => {};
    return sim;
  };
  const bossMath = [];
  for (const fraction of [-1, 0, 0.1, 0.4, 0.400000002, 0.7, 0.700000002, 0.9, 0.900000002, 1, 2]) {
    bossMath.push({ kind: 'segment', input: fraction, result: d.bossSegOf(fraction) });
    for (let segment = 0; segment < d.bossSegN(); segment++) bossMath.push({ kind: 'fraction', input: fraction, segment, result: d.bossSegFrac(fraction, segment) });
  }
  for (let segment = -1; segment <= 5; segment++) {
    bossMath.push({ kind: 'scale', input: segment, result: d.bossScaleF(segment) },
      { kind: 'invulnerability', input: segment, result: d.bossInvulnS(segment) },
      { kind: 'talk', input: segment, result: d.siegeTalkS(segment) });
  }
  for (let size = 0; size <= 7; size++) bossMath.push({ kind: 'slots', input: size, result: d.bossSlotPlan(size) },
    { kind: 'offset', input: size, result: d.bossSlotOff(size) });
  for (const counts of [[0,0,0],[2,1,1],[0,2,1],[0,0,1],[0,0,0,1]]) bossMath.push({ kind: 'open', input: counts, result: d.siegeOpenStage(counts) });
  const bossAnchors = [];
  for (const side of ['SWARM', 'STEEL']) {
    const sim = context(side);
    const sites = sim.towerSites[0].map(site => ({ frac: site.frac,
      ...Object.fromEntries(['SWARM','STEEL'].filter(s => site[s]).map(s => [s, [site[s].x,-site[s].z]])),
      normals: Object.fromEntries(['SWARM','STEEL'].filter(s => site[s]).map(s => [s, [site[s].nx,-site[s].nz]])) }));
    for (let stage = 0; stage < d.SIEGE.STAGES.length; stage++) for (let index = 0; index < 5; index++) {
      const result = sim._bossAnchor(stage, index);
      bossAnchors.push({ side, stage, index, sites, lane: sim.lanes[0].map(p => [p[0],-p[1]]),
        base: [sim.basePos[side][0],-sim.basePos[side][1]], result: [result.x,-result.z] });
    }
  }
  const bossSync = [];
  for (const ch of Object.keys(d.CHARACTERS)) {
    const side = d.CHARACTERS[ch].side === 'MERC' ? 'STEEL' : d.CHARACTERS[ch].side;
    const sim = context(side), h = sim.addHero(side, 'b1', ch), initial = input(h), steps = [];
    for (const [index, fraction] of [0.91,0.899,0.699,0.399,0.8,0].entries()) {
      sim.t = 10 + index * 5;
      h.hp = Math.round(h.maxHp * fraction); h.sp = 0; h.dead = h.hp <= 0;
      sim.events.length = 0;
      sim._bossSync(h.sq);
      steps.push({ now: sim.t, fraction, result: input(h), events: sim.events.filter(e => e.e === 'bossSeg').map(e => e.seg) });
    }
    bossSync.push({ initial, steps });
  }
  const siegeGates = [];
  const gateSim = context();
  for (const enabled of [false,true]) for (const hero of [false,true]) for (const stage of [-1,0,1,2])
    for (const open of [0,1,2]) for (const left of [0,1,2]) for (const until of [9,10,11]) {
      const sim = gateSim; sim.siege = enabled; sim._siegeOpen.STEEL = open;
      sim._bossLeft.STEEL = [left,left,left]; sim._talkUntil.STEEL = [until,until,until];
      const target = { hero, side:'STEEL', ...(stage >= 0 ? {sg:stage}: {}) };
      siegeGates.push({ enabled, hero, stage, open, left, until, locked: sim.siegeLocked(target), floor: sim.siegeHpFloor(target) });
    }
  const siegeDeaths = [];
  for (const side of ['STEEL','SWARM']) for (const size of [3,5]) {
    const sim = context(side,size), bosses = [];
    for (let slot=0;slot<size;slot++) bosses.push(sim.addHero(side,slot === 0 ? 'b1' : `b${slot+1}`,side === 'STEEL' ? 't01':'s01'));
    const initial = state(sim), steps = [];
    for (const boss of bosses) {
      sim.events.length = 0; boss.hp = 0;
      sim._kill(boss,null);
      steps.push({ now:sim.t, stage:boss.sg, state:state(sim), permanent_death:boss.respawnAt===Infinity,
        events:sim.events.filter(e=>['siege','siegeTalk','bossDown'].includes(e.e)).map(e=>({type:e.e==='siegeTalk'?'siege_talk':e.e==='bossDown'?'boss_down':'siege',stage:e.stage??e.sg})) });
    }
    siegeDeaths.push({ side,size,initial,steps });
  }
  const siegeDamage = [];
  for (const kind of ['boss','tower','base']) for (const killer of ['human','ally_bot','npc','none'])
    for (const gate of ['open','locked','boss_alive','talk','talk_done']) for(const amount of [80,160]) {
      const sim = context(), target = kind === 'boss' ? sim.addHero('STEEL','b1','t01')
        : [...sim.ents.values()].find(e=>e.side==='STEEL'&&e.kind===kind);
      if (!target) throw new Error(`Original siege target missing: ${kind}`);
      Object.assign(target,{hp:100,maxHp:100,sp:0,maxSp:0,armor:0,invUntil:0});
      if(kind==='boss')target.sq.bossSeg=3;
      const stage = target.sg;
      sim._siegeOpen.STEEL = gate==='locked' ? stage-1 : stage;
      sim._bossLeft.STEEL[stage] = gate==='boss_alive' ? 1 : 0;
      sim._talkUntil.STEEL[stage] = gate==='talk' ? 11 : 10;
      const attacker = killer==='none' ? null : {id:999,pid:killer==='ally_bot'?'b99':'p1',hero:killer!=='npc',kind:killer==='npc'?'soldier':'robot',
        ch:'t04',side:'SWARM',x:0,z:0,y:0,hp:100,maxHp:100,sp:0,maxSp:0,mods:[],buffs:{},money:0,kn:0,upg:{},dmgOut:0};
      sim.ents = new Map([[target.id,target]]);
      if(attacker){sim.ents.set(999,attacker);if(attacker.hero)sim.heroes.set(attacker.pid,attacker);}
      const initial = input(target), initialState = state(sim), by = attacker ? input(attacker):null;
      sim._damage(target,amount,attacker,0);
      siegeDamage.push({kind,killer,gate,amount,input:initial,attacker:by,initial_state:initialState,result:input(target),
        damage_out:attacker?.dmgOut||0});
    }
  const bossRevive = [];
  for(const side of ['STEEL','SWARM']) {
    const sim=context(side),h=sim.addHero(side,'b1',side==='STEEL'?'t01':'s01');
    h.hp=0;h.dead=true;h.respawnAt=Infinity;
    sim._reviveBody(h,0.5);
    bossRevive.push({side,hp:h.hp,dead:h.dead,permanent_death:h.respawnAt===Infinity});
  }
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const normalized = gameSource.replace(/\r\n/g,'\n'), start = normalized.indexOf('\n  _updateBossBar('), end = normalized.indexOf('\n  }\n',start);
  if(start<0||end<0)throw new Error('Missing original BOSS HUD method');
  const updateBar = new Function('THREE','CHARACTERS','bossSegN',
    `return function ${normalized.slice(start+1,end+4).trimStart().slice('_updateBossBar'.length)}`)(THREE,d.CHARACTERS,d.bossSegN);
  const bossView = [];
  for(const scenario of [
    {name:'view hysteresis',steps:[{now:0},{now:1,p:[1000,10,-30]},{now:3},{now:3.001},{now:4,p:[0,10,-30]},{now:5,hp:0}]},
    {name:'obstacle endpoint tolerance',steps:[{now:0,cover:2},{now:1,cover:0.5},{now:2,cover:1},{now:3,second:true,second_p:[0,10,-10]}]},
    {name:'camera near plane',steps:[{now:0,p:[0,10,-0.05]},{now:1,p:[0,10,-0.1]},{now:2,p:[0,10,10]},{now:5.001}]},
    {name:'stable equal-distance ties',steps:[{now:0,second:true,second_p:[0,10,-30]},{now:1,hp:0},{now:2,remove_second:true}]},
  ]) {
    const camera = new THREE.PerspectiveCamera(70,16/9,0.1,3500); camera.position.set(0,10,0);camera.updateMatrixWorld();
    const entries=[1,2].map(id=>({id,pid:`b${id}`,ch:id===1?'t01':'s01',side:'STEEL',isBoss:id===1,bossSeg:1,
      hp:100,max:100,sp:50,maxSp:50,dead:false,mesh:{visible:true,position:new THREE.Vector3(0,10,id===1?-30:-10)}}));
    let payload=null, coverBy=0;
    const ctx={cfg:{defSide:'STEEL'},camera,ents:new Map(entries.map(e=>[e.id,e])),
      _entAimPoint:e=>e.mesh.position,_obstHitT:(_x,_y,_z,x,y,z)=>coverBy>0?camera.position.distanceTo(new THREE.Vector3(x,y,z))-coverBy:null,
      hud:{bossBar:value=>{payload=value;}}};
    const steps=[];
    for(const step of scenario.steps){
      if(step.p)entries[0].mesh.position.fromArray(step.p);
      if(step.hp!=null)entries[0].hp=step.hp;
      if(step.second)entries[1].isBoss=true;
      if(step.second_p)entries[1].mesh.position.fromArray(step.second_p);
      if(step.remove_second)ctx.ents.delete(2);
      coverBy=step.cover||0;
      updateBar.call(ctx,step.now);
      steps.push({now:step.now,cover:coverBy,targets:[...ctx.ents.values()].map(e=>({id:e.id,character:e.ch,position:e.mesh.position.toArray(),boss:e.isBoss,hp:e.hp})),
        result:{active_id:ctx._activeBossId??0,shown:payload!==null,phase:payload?.phase||0}});
    }
    bossView.push({name:scenario.name,steps});
  }
  return {rules,fixtures:{bossMath,bossAnchors,bossSync,siegeGates,siegeDeaths,siegeDamage,bossRevive,bossView}};
}
