// Run the original missile tick and report gates, keeping visual deflection separate from damage.
export function missileDefenseReferences(d, BattleSim, config, makeRng) {
  const template = new BattleSim(config);
  const point = e => [e.x, e.y || 0, -e.z];
  const hero = (id = 2, side = 'SWARM') => ({ id, pid: id, hero: true, ch: 't05', kind: 'robot',
    side, x: 0, y: 20, z: 100, ry: 0, hp: 100, dead: false, mods: [], buffs: {}, money: 0,
    abil: { light: 1, heavy: 1, def: 1, atk: 1 } });
  const missile = extra => ({ id: 9, byId: 1, side: 'STEEL', tid: 2, x: 0, y: 20, z: 0,
    ox: 0, oy: 20, oz: 0, speed: 40, range: 150, ttl: 5, dmg: 73, pen: 11, r: 14,
    hp: 70, maxHp: 70, ...extra });
  const input = e => ({ id: e.id, character: e.hero ? e.ch : '', kind: e.kind, side: e.side,
    position: point(e), hp: e.dead ? 0 : e.hp, yaw: e.ry || 0,
    carriers: (e.sq?.kamis || []).map(k => k.id),
    status: { phase_until: e.phaseUntil || 0, reflect_until: e.reflectUntil || 0,
      reflect_arc: e.reflectArc ?? 120 * Math.PI / 180, blind_until: e.blindUntil || 0, emp_until: e.empUntil || 0 } });
  const state = m => ({ id: m.id, actor: m.byId, target: m.tid, side: m.side, position: point(m),
    origin: [m.ox, m.oy, -m.oz], speed: m.speed, range: m.range, ttl: m.ttl, dmg: m.dmg, pen: m.pen,
    r: m.r, hp: m.hp, max_hp: m.maxHp, lost: !!m.lost,
    velocity_components: [m.vx || 0, m.vy || 0, -(m.vz || 0)] });
  const context = actors => {
    const sim = Object.create(template);
    sim.ents = new Map(actors.map(e => [e.id, e]));
    sim.heroes = new Map(actors.filter(e => e.hero).map(e => [e.pid, e]));
    sim.events = []; sim.t = 10; sim.over = false; sim.missiles = [];
    sim.hologramDecoys = []; sim.visionUntil = { STEEL: 0, SWARM: 0 };
    sim._freeMissileAt = i => sim.missiles.splice(i, 1);
    return sim;
  };
  const counted = callback => {
    const saved = Math.random, random = makeRng(42);
    let draws = 0;
    Math.random = () => { draws++; return random(); };
    try { callback(); return draws; } finally { Math.random = saved; }
  };
  const decoy = extra => ({ id: 10, kind: 'drone_wingman', side: 'SWARM', x: 0, y: 20, z: 20,
    hp: 100, dead: false, ...extra });
  const kami = extra => ({ id: 30, kind: 'kami', kami: true, side: 'SWARM', x: 0, y: 20, z: 25,
    hp: 100, ...extra });
  const missileDefenses = [];
  const scenarios = [
    { name: 'hologram nearer than body', decoys: [decoy()] },
    { name: 'strict attraction boundary', decoys: [decoy({ x: 40, z: 0 })] },
    { name: 'inside attraction boundary', decoys: [decoy({ x: Math.fround(39.99), z: 0 })] },
    { name: 'outside attraction boundary', decoys: [decoy({ x: Math.fround(40.01), z: 0 })] },
    { name: 'full altitude distance', decoys: [decoy({ x: 1, y: 60, z: 0 })] },
    { name: 'stable attraction ties', decoys: [decoy({ x: 20, z: 0 }), decoy({ id: 11, x: -20, z: 0 })] },
    { name: 'nearest valid attraction', decoys: [decoy({ x: 30, z: 0 }), decoy({ id: 11, x: 20, z: 0 })] },
    { name: 'dead depleted and wrong-side decoys', decoys: [decoy({ hp: 0 }), decoy({ id: 11, dead: true }), decoy({ id: 12, side: 'STEEL' })] },
    { name: 'dead original target still attracts', target: { dead: true }, decoys: [decoy()] },
    { name: 'absent original target cannot attract', missing: true, decoys: [decoy()] },
    { name: 'expired TTL cannot attract', missile: { ttl: 0.05 }, decoys: [decoy()] },
    { name: 'lost missile cannot attract', missile: { lost: true, vx: 0, vy: 0, vz: 40 }, decoys: [decoy()] },
    { name: 'decoy death removes missile', decoys: [decoy()], changes: [{}, { id: 10, dead: true }] },
    { name: 'decoy disappearance removes missile', decoys: [decoy()], changes: [{}, { remove: 10 }] },
    { name: 'phase precedes near fuse', target: { z: 8, phaseUntil: 11 } },
    { name: 'phase loss survives exit and target removal', target: { z: 30, phaseUntil: 11 }, changes: [{}, { id: 2, phaseUntil: 0 }, { remove: 2 }] },
    { name: 'phase outside source range', target: { z: 30, phaseUntil: 11 }, missile: { range: 1 } },
    { name: 'expired phase permits fuse', target: { z: 8, phaseUntil: 10 } },
    { name: 'nonhero phase ignored', target: { hero: false, kind: 'heli', z: 8, phaseUntil: 11 } },
    { name: 'phase wins simultaneous reflection', target: { z: -8, phaseUntil: 11, reflectUntil: 11 } },
    { name: 'phase movement still collides', target: { z: 30, phaseUntil: 11 }, blocked: true },
    { name: 'front reflection harmless', target: { z: -8, reflectUntil: 11 } },
    { name: 'rear reflection permits blast', target: { z: 8, reflectUntil: 11 } },
    { name: 'expired reflection permits blast', target: { z: -8, reflectUntil: 10 } },
    { name: 'nonhero reflection ignored', target: { hero: false, kind: 'heli', z: -8, reflectUntil: 11 } },
    { name: 'zero horizontal offset cannot reflect', target: { z: 0, y: 25, reflectUntil: 11 } },
    { name: 'tiny horizontal offset cannot reflect', target: { z: -Math.fround(0.009), reflectUntil: 11 } },
    { name: 'horizontal reflection threshold', target: { z: -Math.fround(0.011), reflectUntil: 11 } },
    { name: 'zero arc uses source default', target: { z: -8, reflectUntil: 11, reflectArc: 0 } },
    { name: 'front reflection wins range and obstacle', target: { z: -8, reflectUntil: 11 }, missile: { range: 1 }, blocked: true },
    { name: 'reflection only at fuse', target: { z: -30, reflectUntil: 11 } },
    { name: 'expired TTL wins reflection', target: { z: -8, reflectUntil: 11 }, missile: { ttl: 0.05 } },
    { name: 'missing launcher preserves raw warhead', noOwner: true, target: { z: 8 } },
    { name: 'dead launcher preserves raw warhead', deadOwner: true, target: { z: 8 } },
    { name: 'active drone attack carrier attracts', target: { kind: 'drone' }, kamis: [kami()] },
    { name: 'carrier overrides nearer hologram using original target', target: { kind: 'drone' }, decoys: [decoy({ z: 2 })], kamis: [kami()] },
    { name: 'nearest carrier and stable ties', target: { kind: 'drone' }, kamis: [kami({ x: 30, z: 0 }), kami({ id: 31, x: -30, z: 0 })] },
    { name: 'no forty-metre carrier cap', target: { kind: 'drone' }, kamis: [kami({ z: 80 })] },
    { name: 'depleted carrier cannot override hologram', target: { kind: 'drone' }, decoys: [decoy()], kamis: [kami({ hp: 0 })] },
    { name: 'non-drone owner cannot attract to carrier', kamis: [kami()] },
    { name: 'carrier destruction removes guided missile', target: { kind: 'drone' }, kamis: [kami()], changes: [{}, { remove: 30 }] },
    { name: 'dead drone owner still redirects', target: { kind: 'drone', dead: true }, kamis: [kami()] },
    { name: 'lost missile ignores attack carrier', target: { kind: 'drone' }, kamis: [kami()], missile: { lost: true, vz: 40 } },
    { name: 'expired TTL ignores attack carrier', target: { kind: 'drone' }, kamis: [kami()], missile: { ttl: 0.05 } },
    { name: 'next frame can divert carrier target to hologram', target: { kind: 'drone' }, decoys: [decoy({ z: 5 })], kamis: [kami()] },
  ];
  for (const arc of [60, 120, 180]) for (const error of [-0.01, 0, 0.01]) {
    const angle = arc * Math.PI / 360 + error;
    scenarios.push({ name: `reflection sector ${arc}/${error}`, target: {
      x: -Math.fround(Math.sin(angle) * 8), z: -Math.fround(Math.cos(angle) * 8),
      reflectUntil: 11, reflectArc: arc * Math.PI / 180 } });
  }
  for (const scenario of scenarios) {
    const target = { ...hero(), ...scenario.target };
    const owner = { ...hero(1, 'STEEL'), dead: !!scenario.deadOwner };
    const decoys = (scenario.decoys || []).map(e => ({ ...e }));
    const kamis = (scenario.kamis || []).map(e => ({ ...e }));
    target.sq = { kamis };
    const actors = [owner, target, ...decoys, ...kamis];
    const sim = context(actors);
    if (scenario.missing) sim.ents.delete(2);
    if (scenario.noOwner) sim.ents.delete(1);
    const m = missile(scenario.missile);
    sim.missiles = [m]; sim.hologramDecoys = decoys;
    sim._losGrid = true; sim._losBlocked = () => !!scenario.blocked;
    sim._unitLev = () => 0;
    const blasts = [];
    sim._blast = (by, definition, x, z, y, level, friendly, amount) => blasts.push({
      side: by.side, definition, position: [x, y, -z], level: level ?? -1, friendly, amount });
    const steps = [];
    for (const change of scenario.changes || [{}, {}, {}]) {
      if (!sim.missiles.length) break;
      if (change.remove) sim.ents.delete(change.remove);
      if (change.id) Object.assign(sim.ents.get(change.id), change);
      sim.events = []; blasts.length = 0;
      const active = [...sim.ents.values()].map(input), before = state(m);
      const draws = counted(() => sim._tickMissiles(0.05));
      steps.push({ actors: active, before, after: state(m), alive: !!sim.missiles.length, draws,
        blasts: structuredClone(blasts), events: sim.events.filter(e => e.e === 'reflect_hit' || e.e === 'boom' && !e.sam).map(e => ({
          type: e.e === 'reflect_hit' ? 'reflect_hit' : 'missile_deflect', position: [e.x, e.y || 0, -e.z],
          ...(e.e === 'reflect_hit' ? { actor: e.pid, deflected: e.deflected } : { radius: e.r, side: e.side }) })) });
    }
    missileDefenses.push({ name: scenario.name, delta: 0.05, now: 10,
      decoys: decoys.map(e => e.id), blocked: !!scenario.blocked, steps });
  }
  const missileReportGates = [],missileReportRanges=[];
  const reportCase=(character,slot,level,gate,friendly,point={})=>{
    const h={...hero(1,'STEEL'),ch:character,kind:d.CHARACTERS[character].kind,z:0,
      aiming:gate!=='aim_release',blindUntil:gate==='blind'?11:gate==='expired'?10:0,
      empUntil:gate==='emp'?11:gate==='expired'?10:0,phaseUntil:gate==='phase'?11:0,dead:gate==='dead'};
    h.abil[slot]=level;
    const sim=context([h]),m=missile({side:friendly?h.side:'SWARM',z:10,hp:1,...point});
    sim.missiles=[m];sim.over=gate==='over';
    // Isolate the report's own faction, status, aim and range gates after the
    // shared weapon budget has been accepted; cadence is covered separately.
    sim._gateFire=()=>true;
    const before=state(m),draws=counted(()=>sim.hitMissile(1,9,slot));
    if(!Number.isFinite(m.hp)||!Number.isFinite(h.money))throw new Error('Non-finite original missile report result');
    return {character,slot,level,gate,friendly,precheckedWeaponGate:true,input:input(h),missile:before,aiming:h.aiming,
      over:sim.over,damage:1-m.hp,alive:!!sim.missiles.length,bounty:h.money,draws};
  };
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
    for (const gate of ['plain','blind', 'emp', 'expired', 'dead', 'over', 'aim_release', 'phase'])
      for(const friendly of [false,true])missileReportGates.push(reportCase(character,slot,level,gate,friendly));
    const maximum=d.heroWeapon(character,slot,level,true).range*d.RANGE_TOL;
    for(const axis of ['planar','vertical','diagonal'])for(const factor of [1-2e-7,1,1+2e-7]) {
      const distance=maximum*factor;
      // Identical representable coordinates separate range math from the
      // native scene boundary; the original API still decides every outcome.
      const point={x:axis==='vertical'?0:Math.fround(distance*(axis==='diagonal'?.6:1)),
        y:axis==='vertical'?Math.fround(20+distance):20,z:axis==='diagonal'?Math.fround(distance*.8):0};
      missileReportRanges.push(reportCase(character,slot,level,'range_'+axis+'_'+factor,false,point));
    }
  }
  if(!missileReportGates.some(row=>row.damage>0&&!row.friendly)||missileReportGates.some(row=>row.friendly&&row.damage!==0))
    throw new Error('Original missile gate references must cover accepted enemy hits and rejected friendly hits');
  const missileSkillIntercepts = [];
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['def', 'atk']) for (let level = 1; level <= 4; level++) {
    const ability = d.heroAbility(character, slot, level);
    if (ability.fx !== 'intercept') continue;
    for (const fraction of [0, 0.25, 1]) {
      const h = { ...hero(1, 'STEEL'), x: 5, z: 7 }, radius = ability.r * Math.sqrt(Math.max(0.01, fraction));
      const roster = [missile({ id: 20, side: 'SWARM', x: h.x, z: h.z }),
        missile({ id: 21, side: 'SWARM', x: h.x + Math.fround(radius - 0.01), z: h.z, y: 500 }),
        missile({ id: 22, side: 'SWARM', x: h.x + Math.fround(radius + 0.01), z: h.z }),
        missile({ id: 23, side: 'STEEL', x: h.x, z: h.z }),
        missile({ id: 24, side: 'SWARM', x: h.x, z: h.z - Math.fround(radius), y: 200 })];
      const sim = context([h]); sim.missiles = roster;
      const before = roster.map(state);
      const draws = counted(() => sim._castEffect(h, ability, 999, -999, fraction));
      missileSkillIntercepts.push({ character, slot, level, fraction, input: input(h), missiles: before,
        remaining: sim.missiles.map(m => m.id), order: sim.events.filter(e => e.sam).map(e => e.missileId),
        vision: sim.visionUntil.STEEL, bounty: h.money, draws });
    }
  }
  return { missileDefenses, missileReportGates,missileReportRanges, missileSkillIntercepts };
}
