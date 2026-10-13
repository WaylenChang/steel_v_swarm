// Offline reference evaluation; runtime consumes only the generated fixtures.
export function combatReferences(d, BattleSim, config, buildings) {
  const sim = new BattleSim(config);
  sim.ents.clear();
  sim.heroes.clear();
  sim.curWeatherVec = { fog: 0 };
  const visibility = [];
  for (const kind of ['robot', 'drone', 'soldier', 'tower', 'base']) {
    for (const aiming of [false, true]) {
      const observer = { id: 1, kind, side: 'STEEL', hp: 100, x: 0, z: 0, y: 0,
        hero: kind === 'robot' || kind === 'drone', aiming };
      sim.ents = new Map([[1, observer]]);
      sim._visMemo = null;
      // Custom source arrays bypass the source's tick-local entity visibility memo.
      const sources = sim._visionSources('STEEL').map(s => [...s]);
      const radius = sources[0][2];
      for (const distance of [radius - .01, radius, radius + .01]) {
        for (const height of [0, 200]) {
          const target = { id: 2, kind: 'heli', side: 'SWARM', hp: 100, x: distance, z: 0, y: height };
          visibility.push({ kind, aiming, distance, height, radius, eye: sim._eyeY(observer),
            target: sim._tgtY(target), result: sim._visibleTo(target, 'STEEL', sources) });
        }
      }
    }
  }
  const fan = [];
  // Isolate target selection and per-bin damage from pending status/evasion rules.
  sim._gateFire = () => true;
  sim._heroDmg = (_, def) => def.dmg;
  sim._applyHitElem = () => {};
  sim._visionSources = () => [[0, 0, 10000, d.LOS.EYE_M]];
  const scenarios = [
    { name: 'near screens rear', targets: [[0, 18, 0, 'soldier'], [0, 35, 0, 'soldier']] },
    { name: 'equal-distance insertion order', targets: [[0, 25, 0, 'soldier'], [0, 25, 0, 'soldier']] },
    { name: 'separate bins', targets: [[-6, 35, 0, 'soldier'], [6, 35, 0, 'soldier']] },
    { name: 'building cap and rear screen', targets: [[0, 22, 0, 'tower'], [0, 55, 0, 'soldier']] },
    { name: 'large off-axis surface', targets: [[20, 25, 0, 'base']] },
    { name: 'behind muzzle', targets: [[0, -20, 0, 'tower']] },
    { name: 'vertical miss', targets: [[0, 30, 60, 'heli']] },
    { name: 'vertical aim', pitch: 1.2, targets: [[0, 20, 50, 'heli'], [0, 45, 0, 'soldier']] },
    { name: 'downward aim', height: 60, pitch: -.7, targets: [[0, 65, 0, 'tank']] },
    { name: 'within eight metres', targets: [[2, 3, 0, 'soldier'], [0, 6, 0, 'soldier']] },
    { name: 'range surface boundary', relative: true, targets: [[0, 1.1, 0, 'soldier'], [.15, 1, 0, 'tower']] },
    { name: 'outside range', relative: true, targets: [[0, 1.5, 0, 'base']] },
  ];
  for (const [character, hero] of Object.entries(d.CHARACTERS)) {
    for (const slot of ['light', 'heavy']) {
      for (let level = 1; level <= 4; level++) {
        const def = d.heroWeapon(character, slot, level, true);
        if (d.aoeClass(def) !== 'fan') continue;
        for (const scenario of scenarios) {
          const h = { id: 1, hero: true, ch: character, kind: hero.kind, side: 'STEEL', hp: 100,
            x: 0, z: 0, y: scenario.height || 0, aiming: true, abil: { [slot]: level }, buffs: [] };
          sim.heroes = new Map([[1, h]]);
          const targets = scenario.targets.map(([x, z, y, kind], i) => ({ id: i + 2, kind, side: 'SWARM',
            hp: 10000, x: x * (scenario.relative ? def.range : 1),
            z: z * (scenario.relative ? def.range : 1), y }));
          sim.ents = new Map(targets.map(t => [t.id, t]));
          const hits = [];
          sim._damage = (target, amount) => hits.push({ id: target.id, amount });
          const pitch = scenario.pitch || 0;
          sim.heroPlasma(1, 0, Math.cos(pitch), slot, [0, 0, h.y + d.LOS.EYE_M], Math.sin(pitch));
          fan.push({ character, slot, level, name: scenario.name, origin: [0, h.y + d.LOS.EYE_M, 0],
            direction: [0, Math.sin(pitch), -Math.cos(pitch)], targets: targets.map(t => ({ id: t.id,
              kind: t.kind, position: [t.x, t.y, -t.z], radius: d.hitR(t), height: d.hitH(t),
              range_factor: sim._altRange(h, t, def) })), hits });
        }
      }
    }
  }
  const altitudeRange = [false, true].flatMap(heavy => [-100, 0, 26, 40, 78, 200].map(gap => ({
    heavy, gap, result: d.altRangeF(gap, heavy) })));
  const occlusion = [];
  const nativePoint = ([x, y, z]) => [x, y, -z];
  for (const rotation of [0, .6, Math.PI / 2]) {
    const box = { x: 0, z: 0, y: 0, hw2: 3, hd2: 5, h: 8, ry: rotation };
    for (const [start, end] of [
      [[-20, 2, 0], [20, 2, 0]], [[-20, 10, 0], [20, 10, 0]],
      [[-20, 2, 15], [20, 2, 15]], [[0, 20, 0], [0, 2, 0]],
      [[0, -2, 0], [0, 20, 0]],
    ]) {
      const hit = buildings.buildingRayHit([box], ...start, ...end);
      occlusion.push({ box: { position: [0, 4, 0], size: [6, 8, 10], rotation },
        start: nativePoint(start), end: nativePoint(end), result: hit != null, fraction: hit });
    }
  }
  const roof = { buildingKey: 'reference-roof', y: 8,
    outer: [[-10, -10], [10, -10], [10, 10], [-10, 10]],
    holes: [[[-2, -2], [2, -2], [2, 2], [-2, 2]]] };
  const roofHit = buildings.buildingRoofIndex([roof]);
  const faces = [];
  for (const [x0, z0, x1, z1] of [[-10, -10, 10, -2], [-10, 2, 10, 10], [-10, -2, -2, 2], [2, -2, 10, 2]]) {
    for (const point of [[x0, 8, z0], [x1, 8, z1], [x1, 8, z0], [x0, 8, z0], [x0, 8, z1], [x1, 8, z1]]) {
      faces.push(nativePoint(point));
    }
  }
  for (const x of [0, 5, 15]) {
    for (const upward of [false, true]) {
      const start = [x, upward ? 2 : 20, 0], end = [x, upward ? 20 : 2, 0];
      const hit = roofHit(...start, ...end);
      occlusion.push({ faces, start: nativePoint(start), end: nativePoint(end), result: hit != null,
        fraction: hit?.f ?? null });
    }
  }
  const blastVolumes = [];
  const robotCharacter = Object.keys(d.CHARACTERS).find(id => d.CHARACTERS[id].kind === 'robot' && d.CHARACTERS[id].side === 'SWARM');
  if (!robotCharacter) throw new Error('Missing source robot blast reference');
  for (const kind of ['soldier', 'robot', 'heli', 'tower', 'base']) {
    const target = { id: 2, kind, side: 'SWARM', hp: 10000, x: 0, z: 0, y: 0,
      hero: kind === 'robot', ...(kind === 'robot' ? { ch: robotCharacter } : {}) };
    // Isolate source blast geometry; pending evasion/status/slab semantics are excluded.
    sim.ents = new Map([[2, target]]);
    sim._slabSep = () => false;
    sim._dodgeP = () => 0;
    sim._missP = () => 0;
    sim._heroDmg = (_, def) => def.dmg;
    sim._applyHitElem = () => {};
    for (const x of [0, d.hitR(target), d.hitR(target) + 2, d.hitR(target) + 10]) {
      for (const y of [-2, 0, d.hitH(target) / 2, d.hitH(target), d.hitH(target) + 2, d.hitH(target) + 10]) {
        const def = { r: 4, dmg: 100 }, hits = [];
        sim._damage = (t, amount) => hits.push(amount);
        sim._blast({ side: 'STEEL' }, def, x, 0, y);
        blastVolumes.push({ kind, character: target.ch || '', impact: [x, y, 0],
          amount: hits[0] || 0, radius: def.r });
      }
    }
  }
  const friendly = { id: 3, kind: 'soldier', side: 'STEEL', hp: 10000, x: 0, z: 0, y: 0 };
  sim.ents = new Map([[3, friendly]]);
  for (const allow of [false, true]) {
    for (const x of [0, 2, 6]) {
      for (const y of [0, 1, 4]) {
        const hits = [];
        sim._damage = (target, amount) => hits.push(amount);
        sim._blast({ side: 'STEEL' }, { r: 4, dmg: 100 }, x, 0, y, null, allow);
        blastVolumes.push({ kind: 'soldier', character: '', side: 'STEEL', friendly: allow,
          impact: [x, y, 0], amount: hits[0] || 0, radius: 4 });
      }
    }
  }
  const lobSafety = [];
  sim._shotOrigin = () => ({ x: 0, z: 0, y: 0, back: 0 });
  sim._blinded = () => false;
  sim._jammed = () => false;
  sim._bodies = h => [h];
  for (const character of Object.keys(d.CHARACTERS)) {
    for (let level = 1; level <= 4; level++) {
      const def = d.heroWeapon(character, 'heavy', level);
      if (d.trajClass(def) !== 'lob') continue;
      const owner = { id: 1, pid: 1, side: 'STEEL', dead: false, aiming: true, x: 0, z: 0, y: 0 };
      sim.heroes = new Map([[1, owner]]);
      sim._heroWeapon = () => ({ id: 'heavy', def });
      for (const factor of [.5, .999, 1, 1.001, 1.5]) {
        // Native physics endpoints use float32 components; evaluate the actual represented boundary.
        const distance = Math.fround(d.lobMinRange(def) * factor);
        let allow;
        sim.events = [];
        sim._blast = (_owner, _definition, _x, _z, _y, _lev, friendly) => { allow = friendly; };
        sim.heroBurst(1, distance, 0);
        if (allow == null) throw new Error('Source safety burst was rejected');
        lobSafety.push({ character, level, distance, friendly: allow, self: sim.events.find(e => e.e === 'boom').self === 1 });
      }
    }
  }
  const friendlyCoreOutcomes = ['SWARM', 'STEEL'].map(side => {
    const match = new BattleSim(config);
    const core = [...match.ents.values()].find(e => e.kind === 'base' && e.side === side);
    core.hp = 0;
    match._kill(core, null);
    return { side, winner: match.winner, over: match.over };
  });
  return { visibility, fanHits: fan, altitudeRange, occlusion, blastVolumes, lobSafety, friendlyCoreOutcomes };
}
