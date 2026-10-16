import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Original AI methods are the oracle; callbacks isolate decisions from native collision/settlement.
export async function botReferences(d, BattleSim, config, makeRng, source) {
  const { BotBrain } = await import(pathToFileURL(join(source, 'server/bots.js')).href);
  const text = (await readFile(join(source, 'server/bots.js'), 'utf8')).replace(/\r\n/g, '\n');
  const capture = name => {
    const value = new RegExp(`const ${name} = ([^;]+);`).exec(text)?.[1];
    if (!value) throw new Error(`Missing source bot constant: ${name}`);
    return new Function(`return (${value});`)();
  };
  const cruise = capture('CRUISE_ALT'), laneJitter = capture('LANE_JITTER_M'), stuck = capture('STUCK');
  const look = /const PUSH_LOOK_M = LANE_JITTER_M \* ([\d.]+)/.exec(text);
  if (!look) throw new Error('Missing source bot lookahead');
  const rules = { cruise, laneJitter, stuck, pushLook: laneJitter * Number(look[1]), shotTrailSeconds: d.shotTrailS(),
    profiles: Object.fromEntries(Object.keys(d.CHARACTERS).map(ch => {
      const role = d.botRoleOf(ch);
      return [ch, { role, tactic: d.botRoleTactic(d.BOT_TACTIC, role), buy: d.botBuyOrder(role) }];
    })) };
  const clone = value => structuredClone(value);
  const statusNames = { empUntil: 'emp_until', blindUntil: 'blind_until', phaseUntil: 'phase_until', freezeUntil: 'freeze_until',
    castLockUntil: 'cast_lock_until', stunUntil: 'stun_until', slowUntil: 'slow_until', slowF: 'slow_factor', confUntil: 'confuse_until',
    stealthUntil: 'stealth_until', rootedUntil: 'rooted_until', clonesUntil: 'clones_until', noReloadUntil: 'no_reload_until',
    noLightReloadUntil: 'no_light_reload_until', noHeavyReloadUntil: 'no_heavy_reload_until', unbalUntil: 'unbalanced_until', supUntil: 'sup_until', supF: 'sup_factor',
    _elemBuildup: 'element_buildup', _elemLastHit: 'element_last_hit', _psnStacks: 'poison_stacks', _sonicStacks: 'sonic_stacks', _staggerStacks: 'stagger_stacks' };
  const peerOf = e => e.pid === 'b1' ? 1 : e.pid === 'b2' ? 2 : 3;
  const input = e => ({ id: e.id, peer: e.hero ? peerOf(e) : 0, character: e.ch || '', kind: e.kind, side: e.side,
    position: [e.x, e.y || 0, -e.z], yaw: e.ry || 0, pitch: e.rx || 0, hp: e.dead ? 0 : e.hp, max_hp: e.maxHp || e.hp,
    shield: e.sp || 0, max_shield: e.maxSp || 0, power: e.mp || 0, max_power: e.maxMp || 0, money: e.money || 0,
    score: e.kn || 0, armor: e.armor || 0, damage_out: e.dmgOut || 0, damaged_at: e.lastHitAt ?? -99,
    ammo: clone(e.ammo || {}), reload_at: Object.fromEntries(Object.entries(e.reloadUntil || {}).filter(([, value]) => value > 0)),
    last_fired_at: clone(e.fireAt || {}), cooldowns: clone(e.acd || {}), upgrades: clone(e.upg || {}),
    aiming: !!e.aiming, defending: !!e.defending, is_bot: e.pid === 'b1' || e.pid === 'b2',
    special: { neutral: !!e.neutral, garrison: !!e.gar, siege_locked: !!e.locked, boss: !!e.sq?.boss, boss_segment: e.sq?.bossSeg || 0 },
    status: Object.fromEntries(Object.entries(statusNames).filter(([name]) => e[name] != null).map(([name, key]) => [key, clone(e[name])])),
    alert: e._alert ? { point: [e._alert.x, -e._alert.z], altitude: e._alert.y ?? e.y ?? 0, at: e._alert.t } : {},
    hidden: e.visible === false });
  const hero = (ch, extra = {}) => {
    const character = d.CHARACTERS[ch], u = d.UNITS[character.kind], mods = character.mods || {};
    const maxHp = Math.round(u.hp * (mods.hp ?? 1)), maxSp = Math.round(u.shield * (mods.sp ?? 1));
    return { id: 1, pid: 'b1', hero: true, ch, kind: character.kind, side: character.side === 'MERC' ? 'STEEL' : character.side,
      x: 0, y: 0, z: 0, ry: 0, rx: 0, hp: maxHp, maxHp, sp: maxSp, maxSp,
      mp: Math.round(u.mp * (mods.mp ?? 1)), maxMp: Math.round(u.mp * (mods.mp ?? 1)), armor: d.heroArmor(ch),
      money: 0, kn: 0, ammo: {}, reloadUntil: {}, fireAt: {}, buffs: {}, mods: [], acd: { def: 0, atk: 0 },
      upg: { lw: 0, hw: 0, def: 0, atk: 0, hp: 0, ar: 0, sp: 0, ch: 0 },
      abil: { light: 1, heavy: 1, def: 1, atk: 1 }, lastHitAt: -99, ...extra };
  };
  const template = new BattleSim(config);
  const lanes = [[[0, 0], [0, 200], [50, 350]], [[80, 0], [80, 350]]];
  const towerSites = [[{ frac: 0.4, SWARM: { x: 0, z: 140 }, STEEL: { x: 10, z: 210 } }], []];
  const basePos = { SWARM: [0, 0], STEEL: [50, 350] };
  const context = actors => {
    const sim = Object.create(template);
    sim.ents = new Map(actors.map(e => [e.id, e])); sim.heroes = new Map(actors.filter(e => e.hero).map(e => [e.pid, e]));
    sim.squads = new Map(); sim.bossHold = new Map(); sim.events = []; sim.missiles = []; sim.t = 0; sim.over = false;
    sim.lanes = clone(lanes); sim.towerSites = clone(towerSites); sim.basePos = clone(basePos);
    sim.curWeatherDyn = d.resolveWeatherDynamics({ clouds: 10, wind: 0, rain: 0, snow: 0, sand: 0, fog: 0, thunder: 0 });
    sim.weatherSurface = null; sim.visionUntil = { SWARM: 0, STEEL: 0 };
    sim._visionSources = () => []; sim._visibleTo = e => e.visible !== false;
    sim._losBlocked = () => false; sim.siegeLocked = e => !!e.locked;
    sim.solidResolve = (_, _x, _z, x, z) => [x, z];
    sim.isBoss = e => !!e.sq?.boss;
    return sim;
  };
  const counted = callback => {
    const saved = Math.random, random = makeRng(42);
    let draws = 0;
    Math.random = () => { draws++; return random(); };
    try { return callback(() => draws); } finally { Math.random = saved; }
  };
  const botMath = [];
  for (const age of [-1, 0, 3, 6, 7]) botMath.push({ type: 'decay', age, result: d.botThreatDecay(age) });
  for (const hp of [0, 50, 100, 200]) for (const max of [0, 100, 400]) for (const salvo of [0, 100]) {
    botMath.push({ type: 'execution', hp, max, salvo, result: d.botExecW(hp, max, salvo) });
  }
  for (const bearing of [-Math.PI, -1, 0, 1, Math.PI]) for (const elevation of [-1, 0, 1]) {
    const halfH = d.botFovHalf('robot'), halfV = d.botFovVerticalHalf('robot');
    const uv = d.bloodScreenUv(bearing, elevation, halfH, halfV), direction = d.bloodDirFromUv(uv.u, uv.v, halfH, halfV);
    botMath.push({ type: 'blood', bearing, elevation, halfH, halfV, uv: [uv.u, uv.v], direction: [direction.bearing, direction.elev] });
  }
  const botSequences = [];
  for (const difficulty of d.BOT_DIFF_KEYS) for (const scenario of [
    { name: 'lane push', ch: 's01' }, { name: 'robot push', ch: 't01' }, { name: 'morph flight', ch: 'm01' },
    { name: 'engage hero', ch: 't09', enemy: true }, { name: 'packed heavy and skills', ch: 's05', enemy: true, packed: true },
    { name: 'support critical armor', ch: 's08', enemy: true, damaged: true, hp: 0.2 },
    { name: 'rally on low armor and shield', ch: 't03', enemy: true, damaged: true, hp: 0.3, shield: 0.3 },
    { name: 'elite shield break', ch: 't11', enemy: true, damaged: true, shield: 0.19 },
    { name: 'rear hit alert', ch: 't04', alert: true }, { name: 'failed LOS heavy', ch: 't09', enemy: true, packed: true, blocked: true },
    { name: 'stun halts lane convergence', ch: 't06', stun: true }, { name: 'slow and confusion', ch: 'm04', slow: true, confuse: true },
    { name: 'freeze halts complete brain', ch: 't03', freeze: true }, { name: 'dead brain reset', ch: 't03', dead: true },
    { name: 'role buy order', ch: 't05', buy: true }, { name: 'empty heavy lazy refill', ch: 't03', enemy: true, refill: true },
    { name: 'boss post hold', ch: 't01', boss: true }, { name: 'boss enrage pushes', ch: 's01', boss: true, enrage: true },
  ]) {
    counted(draws => {
      const h = hero(scenario.ch, { x: 8, z: 45, ry: 0, money: scenario.buy ? 10000 : 0, kn: scenario.buy ? 10000 : 0 });
      h.hp *= scenario.hp ?? 1; h.sp *= scenario.shield ?? 1;
      if (scenario.damaged) h.lastHitAt = 0;
      if (scenario.stun) h.stunUntil = 10;
      if (scenario.slow) { h.slowUntil = 10; h.slowF = 0.4; }
      if (scenario.confuse) h.confUntil = 10;
      if (scenario.freeze) h.freezeUntil = 10;
      if (scenario.dead) h.dead = true;
      if (scenario.refill) { h.ammo.heavy = 0; h.reloadUntil.heavy = 0.5; }
      if (scenario.boss) h.sq = { boss: true, bossSeg: scenario.enrage ? 3 : 0 };
      if (scenario.alert) h._alert = { x: -50, z: -100, y: 30, t: 0 };
      const foeSide = h.side === 'STEEL' ? 'SWARM' : 'STEEL';
      const enemy = { ...hero('s01'), id: 2, pid: 'b2', side: foeSide, x: 8, z: 70, y: 0, hp: 1000, maxHp: 1000, sp: 100, maxSp: 100 };
      const entities = [h];
      if (scenario.enemy) entities.push(enemy);
      if (scenario.packed) entities.push({ id: 3, kind: 'soldier', side: foeSide, x: 10, y: 0, z: 71, hp: 100 },
        { id: 4, kind: 'soldier', side: foeSide, x: 11, y: 0, z: 72, hp: 100 });
      entities.push({ id: 10, kind: 'tower', side: h.side, x: 0, y: 0, z: 140, hp: 1000 });
      const sim = context(entities), actions = [];
      if (scenario.boss) { sim.squads.set('b1', h.sq); sim.bossHold.set('b1', { x: 8, z: 45, r: 50 }); }
      sim._losBlocked = () => !!scenario.blocked;
      sim.botFire = (_, target, slot) => { actions.push({ type: 'fire', target, slot, mode: 'direct' }); return true; };
      sim.heroBurst = (_, x, z) => { actions.push({ type: 'fire', target: 2, slot: 'heavy', mode: 'burst' }); };
      sim.heroPlasma = () => { actions.push({ type: 'fire', target: 2, slot: 'heavy', mode: 'fan' }); };
      sim.heroAim = (_, on) => { actions.push({ type: 'aim', on }); h.aiming = on; };
      sim.heroDefend = (_, on) => { actions.push({ type: 'defend', on }); h.defending = on; };
      sim.heroCast = (_, slot, x, z) => { actions.push({ type: 'cast', slot, aimed: x != null, point: x != null ? [x, -z] : null }); };
      sim.buy = (_, item, lane) => { actions.push({ type: 'buy', item, lane: lane ?? null }); return scenario.buy && item === 'ar' ? null : 'fixture'; };
      const initial = entities.map(input);
      const brain = new BotBrain(sim, 'b1', h.side, 0, difficulty), steps = [];
      for (let frame = 0; frame < 24; frame++) {
        sim.t = frame * 0.125; actions.length = 0;
        brain.update(0.125);
        steps.push({ now: sim.t, actions: clone(actions), actor: input(h), draws: draws(), brain: {
          state: brain.state, progress: brain.prog, target_id: brain._tid, aim_at: brain._aimAt,
          op_at: clone(brain._opAt), op_next: brain._opNext, role: brain._role || '',
          wanted_yaw: brain._wantRy, wanted_pitch: brain._wantRx, stuck_time: brain._stuckT,
          skirt_until: brain._skirtUntil, skirt_side: brain._skirtSide,
          rally_progress: brain._rallyProg, rally_point: brain._rallyAt ? [brain._rallyAt[0], -brain._rallyAt[1]] : null } });
      }
      botSequences.push({ name: scenario.name, difficulty, inputs: initial, steps, lanes: lanes.map(l => l.map(p => [p[0], -p[1]])),
        bases: Object.fromEntries(Object.entries(basePos).map(([side, p]) => [side, [p[0], -p[1]]])),
        tower_sites: towerSites.map(sites => sites.map(site => ({ frac: site.frac,
          ...Object.fromEntries(['STEEL', 'SWARM'].filter(side => site[side]).map(side => [side, [site[side].x, -site[side].z]])) }))),
        blocked: !!scenario.blocked, buy: !!scenario.buy,
        hold: scenario.boss ? { x: 8, z: -45, r: 50 } : null });
    });
  }
  const botOperations = [];
  for (const key of d.BOT_DIFF_KEYS) {
    const brain = Object.create(BotBrain.prototype);
    brain.sim = { t: 0 }; brain.diff = d.botDiffOf(key); brain._opAt = {}; brain._opNext = 0;
    const steps = [];
    for (const [now, kind] of [[0, 'scan'], [0, 'weapon'], [0.15, 'ability'], [0.3, 'scan'], [0.6, 'weapon'],
      [0.9, 'scan'], [1.2, 'defend'], [1.8, 'ability'], [2.4, 'state'], [3, 'buy'], [3.5, 'buy'], [8, 'buy']]) {
      brain.sim.t = now;
      const result = brain._op(kind);
      steps.push({ now, kind, result, op_at: clone(brain._opAt), op_next: brain._opNext });
    }
    botOperations.push({ difficulty: key, steps });
  }
  const botFire = [];
  for (const ch of Object.keys(d.CHARACTERS)) for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
    for (const gate of ['clear', 'blind', 'emp', 'blocked', 'no_power', 'duplicate']) {
      counted(draws => {
        const h = hero(ch), t = hero('s01', { id: 2, pid: 'b2', side: h.side === 'SWARM' ? 'STEEL' : 'SWARM', z: 10, hp: 1000000, maxHp: 1000000 });
        h.abil[slot] = level; h.upg[slot === 'light' ? 'lw' : 'hw'] = level - 1;
        if (gate === 'blind') h.blindUntil = 11;
        if (gate === 'emp') h.empUntil = 11;
        if (gate === 'no_power') h.mp = 0;
        if (gate === 'duplicate') h.fireAt[slot] = 10;
		const extras = d.aoeClass(d.heroWeapon(ch, slot, level)) === 'line'
          ? [{ id: 3, kind: 'soldier', side: t.side, x: 0, y: 0, z: 20, hp: 1000, maxHp: 1000 }] : [];
        const sim = context([h, t, ...extras]); sim.t = 10; sim.curWeatherDyn = null;
        sim._weatherAccuracyPenalty = () => 0; sim._losBlocked = () => gate === 'blocked';
        const hits = []; sim._damage = (victim, amount) => hits.push({ target: victim.id, amount });
        const before = input(h), target = input(t), extraInputs = extras.map(input), accepted = sim.botFire('b1', 2, slot);
        botFire.push({ character: ch, slot, level, gate, input: before, target, accepted, hits, draws: draws(),
          after: input(h), target_after: input(t), extras: extraInputs, extras_after: extras.map(input), shot_count: h._shotN || 0,
          shot_events: sim.events.filter(e => e.e === 'shot').length });
      });
    }
  }
  const botHeavy = [];
  for (const ch of Object.keys(d.CHARACTERS)) for (let level = 1; level <= 4; level++) {
    const definition = d.heroWeapon(ch, 'heavy', level);
    const mode = ['launcher', 'missile'].includes(definition.type) ? 'burst' : definition.type === 'plasma' ? 'fan' : null;
    if (!mode) continue;
    for (const gate of ['clear', 'blind', 'emp', 'no_aim', 'empty', 'no_power', 'duplicate', 'out_of_range']) counted(draws => {
      const h = hero(ch, { aiming: gate !== 'no_aim' }), t = hero('s01', { id: 2, pid: 'b2',
        side: h.side === 'SWARM' ? 'STEEL' : 'SWARM', z: gate === 'out_of_range' ? 10000 : 10, hp: 1000000, maxHp: 1000000 });
      h.abil.heavy = level; h.upg.hw = level - 1;
      if (gate === 'blind') h.blindUntil = 11;
      if (gate === 'emp') h.empUntil = 11;
      if (gate === 'no_power') h.mp = 0;
      if (gate === 'empty') h.ammo.heavy = 0;
      if (gate === 'duplicate') h.fireAt.heavy = 10;
      const sim = context([h, t]); sim.t = 10; sim.curWeatherDyn = null;
      sim._weatherAccuracyPenalty = () => 0; sim._ridgeBlocked = () => false; sim._slabSep = () => false;
      const hits = []; sim._damage = (victim, amount) => hits.push({ target: victim.id, amount });
      const before = input(h), target = input(t);
      if (mode === 'burst') sim.heroBurst('b1', t.x, t.z, t.y);
      else sim.heroPlasma('b1', t.x - h.x, t.z - h.z, 'heavy', null, sim._tgtY(t) - d.LOS.EYE_M);
      const kinds = sim.events.filter(e => ['shot', 'boom', 'plasma'].includes(e.e)).map(e => e.e);
      botHeavy.push({ character: ch, level, mode, gate, input: before, target,
        accepted: kinds.includes(mode === 'burst' ? 'boom' : 'plasma'), hits, draws: draws(),
        after: input(h), target_after: input(t), kinds });
    });
  }
  const botHurt = [];
  const h = hero('t04'), attacker = hero('s01', { id: 2, pid: 'b2', side: 'SWARM', x: 40, y: 20, z: -50 });
  const hurtSim = context([h, attacker]);
  for (const [now, value] of [[0, 100], [3, 40], [6, 10], [13, 5]]) {
    hurtSim.t = now;
    hurtSim._hurtLog(h, attacker, value);
    botHurt.push({ now, value, target: input(h), attacker: input(attacker),
      threat: Object.fromEntries([...h._threat].map(([key, r]) => [`pilot:${key === 'b2' ? 2 : 1}`, { value: r.v, at: r.t, kind: r.k }])),
      alert: { point: [h._alert.x, -h._alert.z], altitude: h._alert.y, at: h._alert.t } });
  }
  const botShotOrigins = [];
  for (const ch of ['t03', 't09', 'm01']) {
    const definition = d.heroWeapon(ch, 'heavy', 1), cap = d.trajClass(definition) === 'fnf' ? d.chaseCapS(definition) : d.flightCapS(definition);
    for (const now of [0, 1, 5, 10]) {
      const actor = hero(ch, { x: 30, z: 20, _trail: [0, 0, 0, 1, 10, 0, 2, 20, 10] });
      hurtSim.t = now;
      const target = [80, 100], result = hurtSim._shotOrigin(actor, definition, ...target, cap);
      botShotOrigins.push({ character: ch, now, current: [30, -20], target: [80, -100], cap,
        trail: [{ at: 0, x: 0, z: 0 }, { at: 1, x: 10, z: 0 }, { at: 2, x: 20, z: -10 }],
        point: [result.x, -result.z], back: result.back });
    }
  }
  return { rules, inputs: ['server/bots.js', 'public/js/botPolicy.js'],
    fixtures: { botMath, botOperations, botSequences, botFire, botHeavy, botHurt, botShotOrigins } };
}
