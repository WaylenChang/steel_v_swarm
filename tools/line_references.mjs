// Source selection and damage references; no runtime dependency on JavaScript.
export function lineReferences(d, BattleSim, config) {
  const sim = new BattleSim(config);
  const lineHits = [];
  for (const [character, hero] of Object.entries(d.CHARACTERS)) {
    for (let level = 1; level <= 4; level++) {
      const def = d.heroWeapon(character, 'heavy', level);
      if (d.aoeClass(def) !== 'line') continue;
      const R = d.lanceR(def), range = def.range;
      const cases = [
        { name: 'front and rear infantry', targets: [[0, 18, 0, 'soldier'], [0, 36, 0, 'soldier']] },
        { name: 'equal-distance insertion order', targets: [[0, 18, 0, 'soldier'], [0, 18, 0, 'soldier']] },
        { name: 'opposite outer zones', targets: [[R, 18, 0, 'soldier'], [-R, 18, 0, 'soldier']] },
        { name: 'tower shuts independent budgets', targets: [[0, 20, 0, 'tower'], [0, 55, 0, 'soldier'], [R, 55, 0, 'soldier']] },
        { name: 'base shields rear', targets: [[0, 30, 0, 'base'], [0, 60, 0, 'tower']] },
        { name: 'many infantry exhaust core', targets: Array.from({ length: 80 }, (_, i) => [0, 15 + i * 2, 0, 'soldier']) },
        { name: 'tall body aimed at roof', origin: [0, 25, 0], targets: [[0, 30, 0, 'tower']] },
        { name: 'vertical band above body', origin: [0, d.TARGET_H.tower + R * d.LANCE.VBAND_F + .01, 0], targets: [[0, 30, 0, 'tower']] },
        { name: 'end cap reaches near surface', length: 24, targets: [[0, 30, 0, 'tower'], [0, 60, 0, 'tower']] },
        { name: 'outside end cap', length: 24, targets: [[0, 50, 0, 'tower']] },
        { name: 'behind origin near cap', targets: [[0, -1, 0, 'soldier'], [0, -20, 0, 'soldier']] },
        { name: 'horizontal edge inside', targets: [[R + d.hitR({ kind: 'soldier' }) - .01, 30, 0, 'soldier']] },
        { name: 'horizontal edge outside', targets: [[R + d.hitR({ kind: 'soldier' }) + .01, 30, 0, 'soldier']] },
        { name: 'upward body crossing', direction: [0, .4, -Math.sqrt(.84)], targets: [[0, 30, 10, 'heli'], [0, 60, 20, 'heli']] },
        { name: 'downward body crossing', origin: [0, 40, 0], direction: [0, -.4, -Math.sqrt(.84)], targets: [[0, 40, 0, 'tower']] },
        { name: 'vertical up', origin: [0, 0, 0], direction: [0, 1, 0], targets: [[0, 0, 30, 'heli'], [R, 0, 60, 'heli']] },
        { name: 'vertical down', origin: [0, 80, 0], direction: [0, -1, 0], targets: [[0, 0, 30, 'heli'], [R, 0, 0, 'tower']] },
        { name: 'near vertical projection', direction: [.1, Math.sqrt(.99), 0], targets: [[0, 0, 30, 'heli']] },
        { name: 'honest range inside', length: range * 1.15, targets: [[0, range + d.hitR({ kind: 'tower' }) - .01, 0, 'tower']] },
        { name: 'honest range outside consumes budget', length: range * 1.15, targets: [[0, range + d.hitR({ kind: 'tower' }) + .01, 0, 'tower']] },
        { name: 'hidden actor excluded', hidden: 2, targets: [[0, 18, 0, 'soldier'], [0, 36, 0, 'soldier']] },
        { name: 'LOS actor excluded', blocked: 2, targets: [[0, 18, 0, 'soldier'], [0, 36, 0, 'soldier']] },
        { name: 'higher target terrain', origin: [0, 52, 0], ground: 50, targets: [[0, 30, 0, 'tower', 70]] },
        { name: 'lower target terrain', origin: [0, 52, 0], ground: 50, direction: [0, -.3, -Math.sqrt(.91)], targets: [[0, 60, 0, 'tower', 20]] },
        { name: 'airborne hero body', origin: [0, 20, 0], targets: [[0, 30, 20, 'drone'], [0, 60, 20, 'robot']] },
        { name: 'hero upper body span', origin: [0, 3, 0], targets: [[0, 30, 0, 'robot']] },
        { name: 'out-of-range tower consumes budget before eligible hero', origin: [0, 101.5, 0], ground: 100,
          direction: [0, -.35, -1], length: range * 1.15,
          targets: [[0, range + 7.01, 0, 'tower', 101.5 - .35 * (range + 7.01)],
            [0, range + 13.01, 0, 'robot', 100.5 - .35 * (range + 13.01)]] },
        { name: 'eligible hero without the out-of-range blocker', origin: [0, 101.5, 0], ground: 100,
          direction: [0, -.35, -1], length: range * 1.15,
          targets: [[0, range + 13.01, 0, 'robot', 100.5 - .35 * (range + 13.01)]] },
      ];
      for (const scenario of cases) {
        const origin = (scenario.origin || [0, 1.5, 0]).map(Math.fround);
        const direction = (scenario.direction || [0, 0, -1]).map(Math.fround);
        const norm = Math.hypot(...direction);
        const [dx, dy, nativeZ] = direction.map(value => value / norm);
        const ground = scenario.ground || 0;
        const oy = origin[1] - ground;
        const owner = { id: 1, pid: 1, hero: true, kind: hero.kind, ch: character, side: 'STEEL',
          x: origin[0], z: -origin[2], y: oy - d.LOS.EYE_M, ay: origin[1], hp: 10000, aiming: true, buffs: [] };
        const targets = scenario.targets.map(([x, z, y, kind, elevation = 0], index) => {
          const ch = Object.keys(d.CHARACTERS).find(id => d.CHARACTERS[id].kind === kind && d.CHARACTERS[id].side === 'SWARM');
          const isHero = ['robot', 'drone', 'morph'].includes(kind);
          return { id: index + 2, x: Math.fround(x), z: Math.fround(z), y: Math.fround(y), kind,
            side: 'SWARM', hp: 10000, hero: isHero, ...(isHero ? { ch, ay: elevation + y + d.hitH({ hero: true, kind, ch }) * d.SELF_F.eye } : {}), ground: elevation };
        });
        sim.ents = new Map(targets.map(target => [target.id, target]));
        sim.heroes = new Map([[1, owner]]);
        sim.missiles = [];
        sim.visionUntil = {};
        sim._heroWeapon = () => ({ id: 'heavy', def });
        sim._bodies = () => [owner];
        sim._gateFire = () => true;
        sim._blinded = () => false;
        sim._jammed = () => false;
        sim._heroDmg = (_, definition) => definition.dmg;
        sim._rollCrit = (_, __, amount) => amount;
        sim._applyHitEmp = () => {};
        sim._applyHitElem = () => {};
        sim._visionSources = () => [];
        sim._visibleTo = target => target.id !== scenario.hidden;
        sim._losBlocked = (...args) => args.at(-1).id === scenario.blocked;
        sim._ridgeBlocked = () => false;
        sim._hgtAt = (x, z) => x === owner.x && z === owner.z ? ground : targets.find(t => t.x === x && t.z === z)?.ground ?? 0;
        const hits = [];
        sim._damage = (target, amount) => hits.push({ id: target.id, amount });
        const length = scenario.length || range;
        sim.heroLance(1, [origin[0], -origin[2], oy], [dx, -nativeZ, dy], length);
        const selected = sim._lanceHits(owner, def, origin[0], -origin[2], oy, dx, -nativeZ, dy, Math.min(length, range * d.altRangeMax(def)))
          .filter(hit => hit.s - d.hitR(hit.t) <= range * sim._altRange(owner, hit.t, def));
        if (selected.length !== hits.length) throw new Error('Source line reference selection/settlement mismatch');
        lineHits.push({ character, level, name: scenario.name, origin, direction: [dx, dy, nativeZ], length: Math.min(length, range * d.altRangeMax(def)),
          targets: targets.filter(target => target.id !== scenario.hidden && target.id !== scenario.blocked).map(target => ({ id: target.id,
            position: [target.x, target.ground + sim._bodySpan(target)[0], -target.z], radius: d.hitR(target), height: d.hitH(target),
            sample_y: target.ground + sim._tgtY(target), relative_y: sim._tgtY(target) - oy,
            range_factor: sim._altRange(owner, target, def) })),
          hits: hits.map((hit, index) => ({ ...hit, zone: selected[index].zone, rank: selected[index].j, repeat: selected[index].q })) });
      }
    }
  }
  const deadShooterReports = [];
  const dead = new BattleSim(config);
  dead.heroes = new Map([[1, { id: 1, pid: 1, hero: true, side: 'STEEL', dead: true }]]);
  dead.ents = new Map([[2, { id: 2, kind: 'soldier', side: 'SWARM', hp: 1000 }]]);
  let settlements = 0;
  dead._damage = () => { settlements++; };
  for (const [name, args] of [['heroHit', [1, 2, 'light']], ['heroLance', [1, [0, 0, 1.5], [0, 1, 0], 50]], ['heroBurst', [1, 0, 20]]]) {
    settlements = 0;
    dead[name](...args);
    deadShooterReports.push({ method: name, settlements });
  }
  const settlementRange = [];
  const rangeSim = new BattleSim(config);
  const shooterCharacter = 't04', targetCharacter = 's06';
  const eye = ch => d.hitH({ hero: true, kind: d.CHARACTERS[ch].kind, ch }) * d.SELF_F.eye;
  for (const slot of ['light', 'heavy']) {
    for (const kind of ['robot', 'tower', 'heli', 'soldier']) {
      for (const height of [0, 26, 78]) {
        for (const ground of [0, 100]) {
          for (const targetGround of [0, 50]) {
            const h = { hero: true, y: height, ay: ground + height + eye(shooterCharacter), buffs: {} };
            const t = { kind, hero: kind === 'robot', y: kind === 'robot' || kind === 'heli' ? 26 : 0,
              ay: kind === 'robot' ? targetGround + 26 + eye(targetCharacter) : undefined };
            const def = d.heroWeapon(shooterCharacter, slot, 1);
            settlementRange.push({ slot, kind, ground, targetGround, height,
              factor: rangeSim._altRange(h, t, def) });
          }
        }
      }
    }
  }
  for (const expiry of [-1, 1]) {
    const h = { hero: true, y: 0, ay: eye(shooterCharacter), buffs: {}, mods: [{ k: 'range', m: 1.4, until: expiry }] };
    const t = { kind: 'tower', y: 0 };
    settlementRange.push({ slot: 'heavy', kind: 'tower', ground: 0, targetGround: 0, height: 0,
      modifier: { factor: 1.4, expiry }, factor: rangeSim._altRange(h, t, d.heroWeapon(shooterCharacter, 'heavy', 1)) });
  }
  return { lineHits, deadShooterReports, settlementRange };
}
