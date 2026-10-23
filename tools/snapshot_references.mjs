// Offline oracle: the original serializer determines public charging summaries.
export function snapshotReferences(d, BattleSim) {
  const context = Object.assign(Object.create(BattleSim.prototype), {t: 12.3, siege: false});
  const fixtures = [];
  const sourcePrivate = ['ammo', 'reloadUntil', 'fireAt', 'achg', 'acd', 'lift', 'charge', 'pitch', 'aiming'];
  const profiles = [...[1, 2, 3, 4].map(level => ({level})), ...[0, 1, 17, 20, 33, 50, 99, 100].map(superLevel => ({level: d.superCombatLvl(superLevel), superLevel}))];
  for (const [character, hero] of [...Object.entries(d.CHARACTERS), ['missing-character', {kind: 'robot', side: 'STEEL'}]]) for (const profile of profiles) {
    const level = profile.level, tier = profile.superLevel == null ? level - 1 : 0;
    for (const queue of [null, [], [12.3], [12.2999, 14.05], [13, 14.05, 19.2], [10, 11], [12.35]]) {
      const entity = {id: 71, hero: true, pid: '17', ch: character, kind: hero.kind,
        side: profile.superLevel == null ? (hero.side === 'MERC' ? 'STEEL' : hero.side) : d.SUPER_SIDE, x: 0, z: 0, y: 0, ry: .7,
        hp: 200, maxHp: 1000, sp: 30, maxSp: 500, mp: 71, maxMp: 150,
        dead: false, money: 123, kn: 57, upg: {lw: tier, hw: tier, def: tier, atk: tier, ...(profile.superLevel == null ? {} : {super: profile.superLevel})},
        abil: {light: level, heavy: level, def: level, atk: level}, acd: {def: 14.05, atk: 12.3}, achg: {},
        ammo: {light: 9876, heavy: 5432}, reloadUntil: {light: 1234}, fireAt: {heavy: 4321},
        lift: 987, charge: .81, pitch: .73, aiming: true, mods: [], buffs: {}};
      if (queue) for (const slot of ['def', 'atk']) entity.achg[slot] = {max: 3, rechargeAt: [...queue]};
      const input = structuredClone(entity);
      const serialized = context._serializeEnt(entity);
      for (const key of sourcePrivate) if (key in serialized) throw new Error('Original private snapshot field unexpectedly became public: ' + key);
      fixtures.push({character, kind: input.kind, side: input.side, now: context.t, upgrades: input.upg,
        cooldowns: input.acd, charges: Object.fromEntries(Object.entries(input.achg).map(([slot, charge]) => [slot, {max: charge.max, recharge_at: charge.rechargeAt}])),
        result: {levels: serialized.ab, cooldowns: serialized.cds, ...(serialized.chg ? {charges: serialized.chg} : {})}});
    }
  }
  const statusFields = {empUntil: ['emp_until', 'emp'], blindUntil: ['blind_until', 'vb'], stunUntil: ['stun_until', 'pz'],
    slowUntil: ['slow_until', 'sl'], confUntil: ['confuse_until', 'cf'], markUntil: ['mark_until', 'mk'],
    unbalUntil: ['unbalanced_until', 'ub'], freezeUntil: ['freeze_until', 'fz'], stealthUntil: ['stealth_until', 'st'], invUntil: ['inv_until', 'iv']};
  const statusFixtures = [];
  for (const hero of [false, true]) for (const remaining of [-1, 0, .049, .05, 1.234, 2.75]) for (const suppression of [0, .347]) {
    const ch = Object.keys(d.CHARACTERS)[0];
    const entity = {id: 71, hero, pid: '17', ch: hero ? ch : '', kind: hero ? d.CHARACTERS[ch].kind : 'soldier',
      side: 'STEEL', x: 0, z: 0, hp: 100, maxHp: 100, sp: 30, maxSp: 100, mp: 50, maxMp: 100,
      money: 71, kn: 3, abil: {light: 1, heavy: 1, def: 1, atk: 1}, acd: {}, upg: {}, mods: [], buffs: {},
      slowF: 0, supF: suppression, supUntil: context.t + remaining,
      bleed: {until: context.t + remaining, dps: 999, pid: 1234},
      cast: {start: context.t - 1, dur: remaining + 1, slot: 'atk'}, castLockUntil: context.t + 10};
    const status = {slow_factor: entity.slowF, sup_factor: suppression, sup_until: entity.supUntil,
      iframe_cooldown_until: 9999, no_reload_until: 9999, phase_damage: 9999, private_target: 1234};
    for (const [key, [native]] of Object.entries(statusFields)) entity[key] = status[native] = context.t + remaining;
    const serialized = context._serializeEnt(entity), expected = {};
    for (const [, [native, short]] of Object.entries(statusFields))
      if (short in serialized) expected[native] = context.t + serialized[short];
    if ('slf' in serialized) expected.slow_factor = serialized.slf;
    if ('hs' in serialized) {expected.sup_until = context.t + serialized.hs; expected.sup_factor = serialized.hsf;}
    if ('bl' in serialized) expected.bleed_until = context.t + serialized.bl;
    const controlFields={freezeLeft:'fz',stunLeft:'pz',slowLeft:'sl',confLeft:'cf',markLeft:'mk',invLeft:'iv',
      empLeft:'emp',blindLeft:'vb',unbalLeft:'ub',bleedLeft:'bl',castLeft:'cst'};
    const controlExpected=Object.fromEntries(Object.entries(controlFields).map(([key,short])=>[key,serialized[short]||0]));
    statusFixtures.push({hero, character: hero ? ch : '', kind: entity.kind, now: context.t, status,
      bleed: {until: entity.bleed.until, dps: entity.bleed.dps, peer: 1234},
      cast: {start: entity.cast.start, duration: entity.cast.dur, slot: 'atk'}, cast_lock: entity.castLockUntil,
      expected, cast_remaining: serialized.cst ?? null, control_expected:controlExpected,
      icon_expected:{stealthLeft:serialized.st||0,slowF:serialized.slf??.6,hiSupLeft:serialized.hs||0,selfMods:serialized.md||[],_buffsLeft:serialized.bf||[]}});
  }
  const buffFixtures = [];
  for (const remaining of [-1, 0, .049, .5, 1.5, 2.5]) {
    const until = context.t + remaining;
    const entity = {id: 71, hero: true, pid: '17', ch: Object.keys(d.CHARACTERS)[0], kind: 'robot', side: 'STEEL', x: 0, z: 0,
      hp: 100, maxHp: 100, sp: 30, maxSp: 100, mp: 50, maxMp: 100, abil: {}, acd: {}, upg: {}, money: 0, kn: 0,
      buffs: {haste: until}, mods: [{k: 'speed', m: 1.5, until, brk: true}]};
    const serialized = context._serializeEnt(entity);
    const expected = (serialized.md || []).map(([key, value, seconds]) => ({until: context.t + seconds, mul: {[key]: value},
      ...(serialized.bf?.length ? {affix: serialized.bf[0][0]} : {})}));
    buffFixtures.push({now: context.t, buffs: [{until, mul: {speed: 1.5}, affix: 'haste', break_on_hit: true, private_target: 1234}], expected});
  }
  const iconBuffs=[];
  for(const remaining of [-1,0,.049,.499,.5,1.5,2.5]) {
    const until=context.t+remaining;
    const buffs=[{until,mul:{speed:1.5,jump:2},break_on_hit:true,private_target:1234},
      {until,mul:{armor:1.4},affix:'hardened'},{until:context.t+10,mul:{speed:1.2},affix:'tempered'}];
    const entity={id:71,hero:true,pid:'17',ch:Object.keys(d.CHARACTERS)[0],kind:'robot',side:'STEEL',
      x:0,z:0,hp:100,maxHp:100,sp:30,maxSp:100,mp:50,maxMp:100,abil:{},acd:{},upg:{},money:0,kn:0,
      mods:buffs.filter(buff=>!buff.affix).flatMap(buff=>Object.entries(buff.mul).map(([k,m])=>({k,m,until:buff.until}))),
      buffs:Object.fromEntries(buffs.filter(buff=>buff.affix).map(buff=>[buff.affix,buff.until]))};
    const serialized=context._serializeEnt(entity);
    iconBuffs.push({now:context.t,buffs,result:{stealthLeft:0,slowF:.6,hiSupLeft:0,selfMods:serialized.md||[],_buffsLeft:serialized.bf||[]}});
  }
  return {snapshotAbilities: fixtures, snapshotStatuses: statusFixtures, snapshotBuffs: buffFixtures, snapshotIconBuffs:iconBuffs,snapshotRoles: roleReferences(d, context)};
}

function roleReferences(d, context) {
  const result = [], ch = Object.keys(d.CHARACTERS)[0], heroSide = d.CHARACTERS[ch].side === 'MERC' ? 'STEEL' : d.CHARACTERS[ch].side;
  const secrets = {owner_id: 404, target: 505, offset: {x: 99, z: 98}, cd: 999, until: 1000,
    definition: {dmg: 9876}, hp: 100, max_hp: 100, armor: 888, speed: 777,
    camp_index: 44, slot: 43, aggro_id: 42, aggro_at: 999, seek: true, retreat: true,
    spy: true, home: {x: 99, z: 98}, respawn_at: 999, damage_budget: 999, body_fixture: true};
  const record = (name, fields, special, expected) => {
    const entity = {id: 71, kind: 'soldier', side: heroSide, x: 0, z: 0, y: 0, hp: 100, maxHp: 100,
      sp: 0, maxSp: 100, mp: 50, maxMp: 100, money: 71, kn: 3, abil: {}, acd: {}, mods: [], buffs: {}, ...fields};
    const serialized = context._serializeEnt(entity);
    for (const key of ['owner', 'ownerPid', 'target', 'offset', 'cd', 'until', 'definition', 'spy', 'home', 'aggroAt'])
      if (key in serialized) throw new Error('Original special-role serializer leaked ' + key);
    result.push({name, kind: entity.kind, side: entity.side, character: entity.hero ? entity.ch : '', peer: entity.hero ? entity.pid : 0,
      hp: serialized.hp, max_hp: serialized.m, upgrades: {...(entity.upg || {})}, now: context.t,
      special: {...secrets, ...special}, expected: expected(serialized), economy: !!serialized.act,
      super_level: serialized.sv ?? null, charred: !!serialized.charred,
      status: entity.lightningScorch ? {lightning_scorch: {hp: 70, states: [['private', 999]]}} : {}});
  };
  for (const garrison of [false, true]) record('third:' + garrison,
    {side: Object.keys(d.THIRD.SIDES)[0], gar: garrison}, {role: 'third', third: true, garrison},
    output => ({role: 'third', third: true, ...(output.gar ? {garrison: true} : {})}));
  for (const follow of [null, 17]) for (const fleeing of [false, true]) record('civilian:' + follow + ':' + fleeing,
    {kind: 'civilian', civ: true, side: '', cs: heroSide, prof: 13, follow, flee: fleeing, spy: true},
    {role: 'civilian', neutral: true, civil_side: heroSide, profession: 13, follow_peer: follow ?? 0, flee: fleeing},
    output => ({role: 'civilian', neutral: true, civil_side: output.cs, profession: output.pf, following: !!output.fo, fleeing: !!output.fl}));
  for (const scale of [0, .5, 1, 2]) for (const collapsed of [false, true]) record('hazard:' + scale + ':' + collapsed,
    {kind: 'car', side: '', sc: scale, collapsed, lightningScorch: {private: 999}}, {role: 'hazard', neutral: true, scale, collapsed, electric: true, vehicle: true},
    output => ({role: 'hazard', neutral: true, ...('sc' in output ? {scale: output.sc} : {}), ...(output.col ? {collapsed: true} : {})}));
  for (const progress of [0, .001, .5, 1, 2]) record('relay:' + progress,
    {kind: 'relay', side: '', charge: d.FIELD.RELAY.CHANNEL_S * progress, chargeSide: heroSide, sc: 1},
    {role: 'hazard', neutral: true, scale: 1, relay_charge: d.FIELD.RELAY.CHANNEL_S * progress, relay_side: heroSide},
    output => ({role: 'hazard', neutral: true, scale: output.sc, ...('cp' in output ? {relay_progress: output.cp, relay_side: output.cps} : {})}));
  for (const role of ['clone', 'summon', 'hologram', 'slab']) {
    const hero = role === 'clone';
    record(role, {hero, isClone: hero, pid: 17, ch, kind: hero ? d.CHARACTERS[ch].kind : role === 'hologram' ? 'decoy_beacon' : role === 'slab' ? 'slab' : 'soldier',
      isSlab: role === 'slab', ang: .7}, {role, angle: .7, height: 6},
    output => ({role: output.clone ? 'clone' : role}));
  }
  record('super clone', {hero: true, isClone: true, pid: 17, ch, kind: d.CHARACTERS[ch].kind, side: d.SUPER_SIDE, upg: {super: 80}}, {role: 'clone'},
    output => ({role: output.clone ? 'clone' : ''}));
  for (const kind of ['kami', 'decoy', 'hyper']) for (const phase of ['flight', 'climb', 'dive']) for (const lost of [false, true]) {
    const model = heroSide.toLowerCase() + '_' + (kind === 'kami' ? ch + '_kami' : kind);
    record('carrier:' + kind + ':' + phase + ':' + lost, {kind, [kind]: true, pid: 17, ch, phase, lost, ry: .7},
      {role: 'carrier', model_key: model, owner_peer: 17, phase, lost},
      output => ({role: 'carrier', model_key: output.s.toLowerCase() + '_' + (kind === 'kami' ? output.ch + '_kami' : output.k), owner_peer: output.pid,
        ...(kind === 'hyper' ? {phase: output.ph ? 'dive' : 'climb'} : {}), ...(output.lost ? {lost: true} : {})}));
  }
  for (const locked of [false, true]) for (const segment of [0, 1, 3]) {
    context.siege = true; context._siegeOpen = {[heroSide]: 1};
    const entity = {hero: true, pid: 17, ch, kind: d.CHARACTERS[ch].kind, side: heroSide, sg: locked ? 2 : 1};
    entity.sq = {boss: true, bossSeg: segment, bodies: [entity], act: 0};
    // The serializer compares body identity; build the squad on the final entity below.
    const complete = {id: 71, x: 0, z: 0, hp: 100, maxHp: 100, sp: 0, maxSp: 100, mp: 50, maxMp: 100,
      money: 0, kn: 0, abil: {}, acd: {}, mods: [], buffs: {}, ...entity};
    complete.sq.bodies = [complete];
    const output = context._serializeEnt(complete);
    result.push({name: 'boss:' + locked + ':' + segment, kind: complete.kind, side: heroSide, character: ch, peer: 17,
      hp: output.hp, max_hp: output.m, upgrades: {}, now: context.t, special: {...secrets, boss: true, boss_segment: segment, siege_stage: complete.sg, siege_locked: locked, boss_down: true},
      expected: {boss: true, boss_segment: output.bs, ...(output.lk ? {siege_locked: true} : {})}, economy: !!output.act, super_level: null, charred: false, status: {}});
  }
  context.siege = false;
  return result;
}
