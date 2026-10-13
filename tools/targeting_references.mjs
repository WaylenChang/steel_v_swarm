import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

// Run the original client seams; the native runtime never loads Three.js.
export async function targetingReferences(d, gameSource, source, BattleSim, config) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n/g, '\n');
  const method = name => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing source targeting method: ${name}`);
    const body = text.slice(start + 1, end + 4).trimStart();
    const scope = { THREE, ...d };
    return new Function(...Object.keys(scope), `return function ${body.slice(name.length)}`)(...Object.values(scope));
  };
  const cone = method('_coneAcquire'), alt = method('_altRangeTo');
  const eff = method('_effRange'), max = method('_maxRange'), tick = method('_tickLock');
  const aimPoint = method('_entAimPoint'), foe = method('_isFoeEnt'), aimTarget = method('_aimTarget');
  const V = p => new THREE.Vector3(...p.map(Math.fround));
  const targetingCone = [], launchRange = [], lockCandidates = [], aimPriority = [];
  const scenarios = [
    { name: 'nearest angular hero', points: [[7, 2, -100], [3, 2, -100]] },
    { name: 'valid anchor resists closer angle', points: [[7, 2, -100], [3, 2, -100]], keep: 1 },
    { name: 'stable equal angles', points: [[7, 2, -100], [-7, 2, -100]] },
    { name: 'outside cone loses anchor', points: [[20, 2, -100], [3, 2, -100]], keep: 1 },
    { name: 'NPC has no cone fallback', points: [[0, 2, -100], [7, 2, -100]], npc: 1 },
    { name: 'hidden anchor rejected', points: [[3, 2, -100], [7, 2, -100]], keep: 1, hidden: 1 },
    { name: 'dead anchor rejected', points: [[3, 2, -100], [7, 2, -100]], keep: 1, dead: 1 },
    { name: 'ally anchor rejected', points: [[3, 2, -100], [7, 2, -100]], keep: 1, ally: 1 },
    { name: 'early obstacle', points: [[3, 2, -100], [7, 2, -100]], blocked: 1, cut: 50 },
    { name: 'one metre obstacle tolerance', points: [[3, 2, -100], [7, 2, -100]], blocked: 1, cut: 99.1 },
    { name: 'full centre range excludes near surface', points: [[0, 2, -120], [0, 2, -119]], reach: 120 },
    { name: 'body origin range differs from camera', points: [[0, 120, 0]], reach: 120 },
    { name: 'zero camera vector', points: [[0, 2, 0]] },
    { name: 'all outside', points: [[20, 2, -100], [-20, 2, -100]] },
    { name: 'just inside angular limit', points: [[100 * Math.tan(.14 - .00001), 2, -100]] },
    { name: 'just outside angular limit', points: [[100 * Math.tan(.14 + .00001), 2, -100]] },
  ];
  for (const scenario of scenarios) for (const offset of [[0, 0, 0], [20, 50, -30], [-100, -50, 100]]) {
    const pos = V(offset), eye = pos.clone().add(V([0, 2, 0]));
    const entries = scenario.points.map((p, i) => {
      const id = i + 1, point = V(pos.clone().add(V(p)).toArray());
      return { id, hero: id !== scenario.npc, side: id === scenario.ally ? 'STEEL' : 'SWARM',
        dead: id === scenario.dead, dimTop: 0, dimH: 0,
        mesh: { position: point, visible: id !== scenario.hidden } };
    });
    const ctx = { side: 'STEEL', pos, camera: { position: eye, getWorldDirection: v => v.set(0, 0, -1) },
      canvas: { clientWidth: 800, clientHeight: 600 }, ents: new Map(entries.map(e => [e.id, e])),
      _lockId: scenario.keep || null, _entAimPoint: aimPoint, _isFoeEnt: foe,
      _obstHitT: () => null };
    // Avoid coordinate-dependent callback rounding; identify the candidate by its centre.
    ctx._obstHitT = (...coords) => entries.find(e => e.id === scenario.blocked &&
      e.mesh.position.toArray().every((x, i) => x === coords[i + 3])) ? scenario.cut : null;
    const reach = scenario.reach || 150;
    targetingCone.push({ name: scenario.name, position: pos.toArray(), eye: eye.toArray(), forward: [0, 0, -1],
      reach, keep: scenario.keep || 0, candidates: entries.map(e => ({ id: e.id, hero: e.hero,
        eligible: e.side !== ctx.side && !e.dead && e.mesh.visible, point: e.mesh.position.toArray(),
        obstruction: e.id === scenario.blocked ? scenario.cut : null })), result: cone.call(ctx, reach)?.id || 0 });
  }
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
    const def = d.heroWeapon(character, slot, level);
    for (const scenario of [
      { name: 'no target' },
      { name: 'lower hero standard eye', hero: true, kind: 'robot', y: 0 },
      { name: 'higher hero standard eye', hero: true, kind: 'robot', y: 100 },
      { name: 'hero at own eye', hero: true, kind: 'robot', y: 42 },
      { name: 'ground NPC ignores terrain elevation', kind: 'tank', y: 100, altitude: 0 },
      { name: 'tower fixed reference eye', kind: 'tower', y: 100, altitude: 0 },
      { name: 'core fixed reference eye', kind: 'base', y: -100, altitude: 0 },
      { name: 'air NPC relative elevation', kind: 'heli', y: 100, altitude: 20 },
      { name: 'high air NPC relative elevation', kind: 'heli', y: 0, altitude: 100 },
      { name: 'surface-clamped shooter', kind: 'tank', y: -100, altitude: 0, surface: 40 },
    ]) {
      const pos = V([0, 40, 0]), eyeHeight = Math.fround(d.heroTargetH(d.CHARACTERS[character].kind, character) * d.SELF_F.eye);
      const surface = scenario.surface ?? 0;
      const ent = scenario.kind ? { hero: !!scenario.hero, kind: scenario.kind, heroY: scenario.altitude || 0,
        mesh: { position: V([0, scenario.y, -100]) } } : null;
      const ctx = { side: 'STEEL', dead: false, pos, _altAG: pos.y - surface, _eyeH: () => eyeHeight,
        _altRangeTo: alt };
      launchRange.push({ character, slot, level, name: scenario.name, position: pos.toArray(),
        eye: pos.clone().add(V([0, eyeHeight, 0])).toArray(), surface,
        target: ent ? { hero: ent.hero, kind: ent.kind, position: ent.mesh.position.toArray(), altitude: ent.heroY } : {},
        range: eff.call(ctx, def, ent), maximum: max.call(ctx, def) });
    }
  }
  const hd = Object.keys(d.CHARACTERS).map(c => d.heroWeapon(c, 'heavy', 1)).find(w => d.trajClass(w) === 'fnf');
  for (const primary of [null, { id: 9, distance: 99, reach: 100 }, { id: 9, distance: 101, reach: 100 }]) {
    for (const flights of [[], [{ id: 1, distance: 99, reach: 100 }],
      [{ id: 1, distance: 100, reach: 100 }, { id: 2, distance: 90, reach: 100 }, { id: 1, distance: 100, reach: 100 }],
      [{ id: 1, distance: 101, reach: 100 }]]) for (const index of [0, 1, 3]) {
      const ents = new Map([primary, ...flights].filter(Boolean).map(t => [t.id,
        { id: t.id, side: 'SWARM', mesh: { position: V([t.distance, 0, 0]) }, reach: t.reach }]));
      let selected = 0;
      const ctx = { side: 'STEEL', pos: V([0, 0, 0]), wdef: { heavy: hd }, _curWeapon: () => ({ def: hd }),
        _aimTarget: () => primary ? ents.get(primary.id) : null, _maxRange: () => 100,
        _effRange: (_, t) => t.reach, _hitR: () => 0, _isFoeEnt: foe,
        ents, bullets: flights.map(t => ({ fnf: true, homing: t.id })), _lockKeepRi: index,
        net: { send: m => { selected = m.id; } }, _clearLockGlow() {} };
      tick.call(ctx, 1);
      lockCandidates.push({ primary: primary || {}, flights, index, result: { id: selected, index: ctx._lockKeepRi } });
    }
  }
  for (const lob of [null, { on: true, ok: false }, { on: true, ok: true }]) {
    for (const exact of [null, { distance: 99 }, { distance: 101 }]) {
      const ent = { id: 1, side: 'SWARM' }, fallback = { id: 2, side: 'SWARM' };
      const ctx = { side: 'STEEL', pos: V([0, 0, 0]), _isFoeEnt: foe,
        _lobFc: lob ? { ...lob, ent } : null,
        _resolveAim: () => ({ ent: exact ? ent : null, point: V([exact?.distance || 0, 0, 0]) }),
        _coneAcquire: () => fallback };
      aimPriority.push({ lob, exact: exact?.distance ?? null, result: aimTarget.call(ctx, 100)?.id || 0 });
    }
  }
  const lockConfirmation = [], sim = new BattleSim(config);
  sim._visibleTo = () => true;
  sim._losBlocked = () => false;
  const eye = ch => Math.fround(d.hitH({ hero: true, kind: d.CHARACTERS[ch].kind, ch }) * d.SELF_F.eye);
  const confirm = (character, level, aiming, scenario) => {
    sim.t = 10;
    const h = { id: 1, pid: 1, hero: true, ch: character, kind: d.CHARACTERS[character].kind,
      side: 'STEEL', x: 0, z: 0, y: 1, ay: 1 + eye(character), hp: 100, aiming, abil: { light: level, heavy: level },
      buffs: {}, aimOffAt: sim.t - (scenario.releaseAge || 0) };
    const t = { id: 2, hero: true, ch: 's01', kind: d.CHARACTERS.s01.kind,
      side: 'SWARM', x: 0, z: 100, y: 1, ay: 1 + eye('s01'), hp: 100 };
    const sq = { side: 'STEEL', lock: scenario.previous || 0, lockAt: sim.t - (scenario.lockAge || 0) };
    sim.squads = new Map([[1, sq]]);
    sim.heroes = new Map([[1, h]]);
    sim.ents = new Map([[1, h], [2, t]]);
    sim.events = [];
    if (scenario.edge) {
      const def = d.heroWeapon(character, aiming ? 'heavy' : 'light', level, true);
      const reach = def.range * sim._altRange(h, t, def) * d.RANGE_TOL * (d.aoeClass(def) === 'fan' ? d.FAN_RANGE_CENTER_F : 1);
      t.z = Math.fround(reach + d.hitR(t) + scenario.edge);
    } else t.z = scenario.distance || 150;
    if (scenario.dead) h.dead = true;
    const before = sq.lockAt;
    sim.heroLock(1, 2);
    lockConfirmation.push({ character, level, aiming, name: scenario.name,
      distance: t.z, previous: scenario.previous || 0, lockAge: scenario.lockAge || 0,
      releaseAge: scenario.releaseAge || 0, dead: !!scenario.dead, accepted: sq.lockAt !== before || sim.events.some(e => e.e === 'lock') });
  };
  for (const character of ['t09', 't04', 's04']) for (let level = 1; level <= 4; level++) {
    for (const aiming of [false, true]) for (const edge of [-.01, .01])
      confirm(character, level, aiming, { name: edge < 0 ? 'near surface inside' : 'near surface outside', edge });
  }
  const cap = d.flightCapS(d.heroWeapon('t09', 'heavy', 1));
  for (const scenario of [
    { name: 'new light lock refuses heavy range' },
    { name: 'same target heavy continuation', previous: 2 },
    { name: 'flight window boundary', previous: 2, releaseAge: cap },
    { name: 'flight window expired', previous: 2, releaseAge: cap + .01 },
    { name: 'lock TTL boundary', previous: 2, lockAge: d.LOCK.TTL },
    { name: 'lock TTL expired', previous: 2, lockAge: d.LOCK.TTL + .01 },
    { name: 'other previous target', previous: 3 },
    { name: 'dead shooter rejected', previous: 2, dead: true },
  ]) confirm('t09', 1, false, scenario);
  return { targetingCone, launchRange, lockCandidates, aimPriority, lockConfirmation };
}
