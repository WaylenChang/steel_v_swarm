import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

export async function missileReferences(d, BattleSim, config, source, gameSource) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const simSource = await readFile(join(source, 'server/sim.js'), 'utf8');
  const vfx = (await readFile(join(source, 'public/js/vfx.js'), 'utf8')).replace(/\r\n/g, '\n');
  const extract = (text, name, scope) => {
    const start = text.indexOf(`export function ${name}(`), end = text.indexOf('\n}', start);
    if (start < 0 || end < 0) throw new Error(`Missing missile geometry seam: ${name}`);
    return new Function(...Object.keys(scope), `return ${text.slice(start + 7, end + 2)}`)(...Object.values(scope));
  };
  const stepFx = extract(vfx, 'stepProjectileFx', {});
  const outlinify = extract((await readFile(join(source, 'public/js/toon.js'), 'utf8')).replace(/\r\n/g, '\n'), 'outlinify',
    { THREE, _ws: new THREE.Vector3(), outlineMaterial: () => new THREE.MeshBasicMaterial({ side: THREE.BackSide }) });
  const meshFactory = extract(vfx, 'projectileMesh', { THREE, COMBAT_ASSETS: {},
    unitGeo: (_, build) => build(), toonMat: color => new THREE.MeshBasicMaterial({ color }), outlinify, stepProjectileFx: stepFx });
  const syncStart = gameSource.indexOf('  _syncMissiles(');
  const scale = Number(/mesh\.scale\.setScalar\(([\d.]+)\)/.exec(gameSource.slice(syncStart))?.[1]);
  const fuseDistance = Number(/Math\.max\(([\d.]+), step\)/.exec(simSource)?.[1]);
  const launchOffset = Number(/const off = i === 0 \? ([\d.]+) :/.exec(simSource)?.[1]);
  const interceptRadius = Number(/missileId:m\.id[^\n]+r: ([\d.]+), side: h\.side, sam: true/.exec(simSource)?.[1]);
  const snapshotScale = Number(/x: Math\.round\(m\.x \* ([\d.]+)\)/.exec(simSource)?.[1]);
  if (!scale || !fuseDistance || !launchOffset || !interceptRadius || !snapshotScale) throw new Error('Missing source missile constants');
  const mesh = meshFactory({ type: 'missile' }, { hue: 0xff6633 });
  mesh.scale.setScalar(scale);
  mesh.updateMatrixWorld(true);
  const parts = [];
  mesh.traverse(o => {
    if (!o.isMesh || o.userData.isOutline) return;
    const positions = o.geometry.getAttribute('position'), vertices = [];
    for (let i = 0; i < positions.count; i++) vertices.push(new THREE.Vector3().fromBufferAttribute(positions, i).applyMatrix4(o.matrixWorld).toArray());
    parts.push({ vertices, indices: o.geometry.index ? [...o.geometry.index.array] : Array.from({ length: vertices.length }, (_, i) => i),
      color: o.material.color.toArray(), opacity: o.material.opacity });
  });
  const missileRays = [];
  for (const origin of [[0, 0, -5], [0, 0, 5], [5, 0, 0], [0, 5, 0], [0, 0, 0], [.2, 0, -5], [.5, 0, -5], [1, 0, -5]]) {
    for (const aim of [[0, 0, 0], [0, 0, -1], [.1, 0, 0]]) {
      const ro = new THREE.Vector3(...origin), rd = new THREE.Vector3(...aim).sub(ro).normalize();
      const ray = new THREE.Raycaster(ro, rd, 0, 10);
      const hit = ray.intersectObject(mesh, true)[0];
      missileRays.push({ origin, direction: rd.toArray(), point: hit?.point.toArray() || null });
    }
  }
  const sim = new BattleSim(config), missileFlight = [];
  for (const scenario of [
    { name: 'moving target', target: [50, 30, 100] },
    { name: 'range escape never reacquires', target: [0, 20, 200], range: 100 },
    { name: 'range boundary stays guided', target: [0, 20, 100], range: 100 },
    { name: 'fuse wins range escape', target: [0, 20, 10], range: 1 },
    { name: 'step-sized fuse', target: [0, 20, 40], delta: .5 },
    { name: 'TTL wins fuse', target: [0, 20, 1], ttl: .05 },
    { name: 'missing target removes silently', missing: 0 },
    { name: 'dead target removes silently', dead: 2 },
    { name: 'tracking obstacle blasts endpoint', blocked: 2 },
    { name: 'lost obstacle blasts endpoint', target: [0, 20, 200], range: 100, blocked: 2 },
    { name: 'lost missile expires silently', target: [0, 20, 200], range: 100, ttl: .3 },
  ]) {
    const m = { id: 9, byId: 1, side: 'STEEL', tid: 2, x: 0, y: 20, z: 0, ox: 0, oy: 20, oz: 0,
      speed: d.BASE_MISSILE.SPEED, dmg: d.UNITS.base.guns.dmg, pen: d.STRUCT_W.base.pen, r: d.STRUCT_W.base.r,
      hp: d.BASE_MISSILE.HP, ttl: scenario.ttl || 5, range: scenario.range || 155 };
    const p = scenario.target || [0, 20, 100];
    const target = { id: 2, x: p[0], y: p[1], z: p[2], hp: 100 };
    sim.missiles = [m];
    sim.ents = new Map([[2, target]]);
    sim._freeMissileAt = i => sim.missiles.splice(i, 1);
    sim._losGrid = true;
    let frame = 0, blast = null;
    sim._losBlocked = () => scenario.blocked === frame;
    sim._samBlast = (_, x, z, y) => { blast = [x, y, -z]; };
    const snapshot = () => ({ position: [m.x, m.y, -m.z], origin: [m.ox, m.oy, -m.oz],
      speed: m.speed, range: m.range, ttl: m.ttl, target: 2, lost: !!m.lost,
      velocity_components: [m.vx || 0, m.vy || 0, -(m.vz || 0)] });
    const steps = [];
    for (; frame < 35 && sim.missiles.length; frame++) {
      if (scenario.missing === frame) sim.ents.clear();
      if (scenario.dead === frame) target.dead = true;
      if (scenario.name === 'moving target') target.x += 1;
      if (m.lost && frame === 2) target.z = 50;
      const targetData = sim.ents.has(2) && !target.dead ? { position: [target.x, target.y, -target.z] } : {};
      const before = snapshot();
      sim._tickMissiles(scenario.delta || .05);
      steps.push({ before, target: targetData, blocked: scenario.blocked === frame, after: snapshot(),
        removed: sim.missiles.length === 0, blast });
    }
    missileFlight.push({ name: scenario.name, delta: scenario.delta || .05, steps });
  }
  const missileDamage = [], missileLines = [];
  const combat = new BattleSim(config);
  combat._bodies = h => [h];
  combat._gateFire = () => true;
  combat._blinded = () => false;
  combat._jammed = () => false;
  combat._freeMissileAt = i => combat.missiles.splice(i, 1);
  combat._lanceHits = () => [];
  combat._hgtAt = () => 0;
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
    const def = d.heroWeapon(character, slot, level, true);
    const scenarios = [{ name: 'ordinary damage', distance: 20 }, { name: 'falloff', distance: def.range },
      { name: 'range inside', distance: Math.fround(def.range * d.RANGE_TOL - .01) },
      { name: 'range outside', distance: Math.fround(def.range * d.RANGE_TOL + .01) },
      { name: 'allied missile', ally: true, distance: 20 }, { name: 'no aim', aiming: false, distance: 20 },
      { name: 'live damage modifier', buff: 1.4, distance: 20 }, { name: 'lethal no blast', hp: 1, distance: 20 }];
    for (const scenario of scenarios) {
      const h = { id: 1, pid: 1, hero: true, kind: d.CHARACTERS[character].kind, ch: character,
        side: 'STEEL', x: 0, y: 1, z: 0, hp: 100, aiming: scenario.aiming !== false,
        abil: { light: level, heavy: level }, buffs: {}, money: 0,
        mods: scenario.buff ? [{ k: 'dmg', m: scenario.buff, until: 1 }] : [] };
      const m = { id: 9, side: scenario.ally ? 'STEEL' : 'SWARM', x: 0, y: 1, z: scenario.distance, hp: scenario.hp || 1000000 };
      const hp = m.hp;
      combat.heroes = new Map([[1, h]]);
      combat.missiles = [m]; combat.events = [];
      combat.hitMissile(1, 9, slot);
      missileDamage.push({ character, slot, level, ...scenario, hp, damage: hp - m.hp,
        removed: combat.missiles.length === 0, bounty: h.money });
    }
    if (d.aoeClass(def) !== 'line') continue;
    const radius = d.lanceR(def);
    for (const point of [[0, 1.5, 20], [radius - .01, 1.5, 20], [radius + .01, 1.5, 20],
      [0, 1.5 + radius - .01, 20], [0, 1.5 + radius + .01, 20], [0, 1.5, -radius / 2],
      [0, 1.5, 40 + radius / 2], [0, 1.5, def.range * d.RANGE_TOL + .01]]) {
      const h = { id: 1, pid: 1, hero: true, kind: d.CHARACTERS[character].kind, ch: character,
        side: 'STEEL', x: 0, y: 0, z: 0, hp: 100, aiming: true, abil: { light: level, heavy: level }, buffs: {}, money: 0 };
      const m = { id: 9, side: 'SWARM', x: point[0], y: point[1], z: point[2], hp: 1e6 };
      combat.heroes = new Map([[1, h]]); combat.ents = new Map([[1, h]]);
      combat.missiles = [m]; combat.events = [];
      combat.heroLance(1, [0, 0, 1.5], [0, 1, 0], 40);
      missileLines.push({ character, slot, level, origin: [0, 1.5, 0], direction: [0, 0, -1], length: 40,
        point: [m.x, m.y, -m.z], damage: 1e6 - m.hp });
    }
  }
  const baseLaunches = [];
  const launchSim = new BattleSim(config);
  launchSim._sandAttackRateMul = () => 1;
  let acquired = true;
  launchSim._acquireTarget = () => acquired ? { id: 2, pid: 2, x: 0, y: 20, z: 100, hero: true } : null;
  const base = { id: 1, side: 'STEEL', x: 0, z: 0 };
  for (const [delta, available] of [[.05, true], [.05, true], [.75, true], [.1, false], [1, false], [.05, true]]) {
    acquired = available; launchSim.events = []; launchSim.missiles = [];
    launchSim._tickBaseGuns(base, d.UNITS.base.guns, delta);
    baseLaunches.push({ delta, available, cooldowns: [...base.gunCd], missiles: launchSim.missiles.map(m => ({
      position: [m.x, m.y, -m.z], speed: m.speed, dmg: m.dmg, r: m.r, hp: m.hp, ttl: m.ttl, range: m.range })) });
  }
  const baseTargets = [], targetSim = new BattleSim(config);
  targetSim._losGrid = null;
  const shooter = { kind: 'base', side: 'STEEL', x: 0, y: 0, z: 0, hp: 3000 };
  const candidates = [
    [['soldier', 40, 0], ['soldier', 60, 0]],
    [['robot', 30, 0], ['soldier', 40, 0]],
    [['robot', 28, 0], ['soldier', 40, 0]],
    [['soldier', 40, 0], ['soldier', -40, 0]],
    [['tower', d.UNITS.base.guns.range + 1, 0], ['soldier', 140, 0]],
    [['drone', 20, d.GAME.GUN_CEIL_M + .01], ['robot', 50, 100]],
    [['drone', 20, d.GAME.GUN_CEIL_M], ['soldier', 80, 0]],
    [['morph', 20, d.GAME.GUN_CEIL_M + .01], ['heli', 80, 20]],
    [['soldier', d.UNITS.base.guns.range - .01, 0]],
    [['soldier', d.UNITS.base.guns.range + .01, 0]],
  ];
  for (const positions of candidates) {
    const targets = positions.map(([kind, z, y], i) => ({ id: i + 1, kind, x: 0, z: Math.fround(z), y: Math.fround(y),
      side: 'SWARM', hp: 100, hero: ['robot', 'drone', 'morph'].includes(kind) }));
    targetSim._tgCandidates = () => targets;
    baseTargets.push({ targets, result: targetSim._acquireTarget(shooter, d.UNITS.base.guns)?.id || 0 });
  }
  const missileSnapshots = [], frameSim = new BattleSim(config);
  frameSim._flushHurt = () => {};
  for (const point of [[-.05, .05, -.05], [.05, -.05, .05], [.15, -.15, .15], [-.15, .15, -.15], [1.23, 4.56, -7.89]]) {
    frameSim.missiles = [{ id: 9, x: point[0], y: point[1], z: -point[2], hp: 69.2, maxHp: 70 }];
    frameSim._frameTickN = -1;
    const packet = frameSim._frame().sm[0];
    missileSnapshots.push({ point, result: { position: [packet.x, packet.y, -packet.z], hp: packet.hp, max_hp: packet.m } });
  }
  return { metadata: { parts, fuseDistance, launchOffset, interceptRadius, snapshotScale },
    fixtures: { missileFlight, missileDamage, missileLines, missileRays, baseLaunches, baseTargets, missileSnapshots } };
}
