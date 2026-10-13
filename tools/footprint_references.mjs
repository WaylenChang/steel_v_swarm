import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

// Run the actual client victim roster, including its 3D section basis and post-budget gates.
export async function footprintReferences(d, gameSource, source) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n/g, '\n');
  const tolerance = /const RANGE_GLOW = \{ SURF_TOL_M: ([\d.]+) \};/.exec(text);
  if (!tolerance) throw new Error('Missing source footprint clearance tolerance');
  const scope = { THREE, ...d, RANGE_GLOW: { SURF_TOL_M: Number(tolerance[1]) },
    ARC_MAXP: Number(/const ARC_MAXP = (\d+);/.exec(text)?.[1]) };
  const method = name => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing source footprint method: ${name}`);
    return new Function(...Object.keys(scope), `return function ${text.slice(start + 1, end + 4).trimStart().slice(name.length)}`)(...Object.values(scope));
  };
  const seams = Object.fromEntries(['_shotVictims', '_reachable', '_shotWarn', '_inShotRange', '_bodyDy',
    '_entAimPoint', '_lancePierced', '_isFoeEnt', '_lobSolve', '_lobVel', '_lob45Vel', '_arcTrace', '_lobLadder'].map(name => [name, method(name)]));
  const V = p => new THREE.Vector3(...p.map(Math.fround));
  const shotFootprints = [];
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
    const def = d.heroWeapon(character, slot, level), area = d.aoeClass(def), reach = def.range;
    const r = area === 'line' ? d.lanceR(def) : 1;
    const base = { kind: 'soldier', position: [0, 0, -30], radius: .5, height: 4, top: 4 };
    const row = (position, flags = {}) => ({ ...base, position, ...flags });
    const cases = [
      { name: 'reticle direct', exact: 1, targets: [row([0, 0, -30])] },
      { name: 'no reticle still permits fan/line', targets: [row([0, 0, -30])] },
      { name: 'far reticle never gates near fan/line', exact: 2, point: [0, 2, -reach * 3], targets: [row([0, 0, -5]), row([0, 0, -reach * 3])] },
      { name: 'hidden first target', exact: 1, targets: [row([0, 0, -30], { visible: false }), row([0, 0, -60])] },
      { name: 'ally first target', exact: 1, targets: [row([0, 0, -30], { ally: true }), row([0, 0, -60])] },
      { name: 'dead visible body consumes line budget', targets: [row([0, 0, -20], { dead: true, radius: 20 }), row([0, 0, -40])] },
      { name: 'neutral visible body consumes line budget', targets: [row([0, 0, -20], { neutral: true, radius: 20 }), row([0, 0, -40])] },
      { name: 'garrison visible body consumes line budget', targets: [row([0, 0, -20], { garrison: true, radius: 20 }), row([0, 0, -40])] },
      { name: 'empty shot', targets: [] },
      { name: 'blocked centre', exact: 1, targets: [row([0, 0, -30], { cut: 1 })] },
      { name: 'range inside', exact: 1, targets: [row([0, 0, -reach - .5 + .01])] },
      { name: 'range outside', exact: 1, targets: [row([0, 0, -reach - .5 - .01])] },
      { name: 'per-target shortened range', exact: 1, targets: [row([0, 0, -reach * .7], { rangeFactor: .5 })] },
      { name: 'measured top above height', exact: 1, targets: [row([0, 0, -30], { top: 7 })] },
    ];
    if (area === 'fan') cases.push(
      { name: 'front screens rear same bins', targets: [row([0, 0, -20]), row([0, 0, -40])] },
      { name: 'stable angular side winners', targets: [row([-5, 0, -30]), row([5, 0, -30])] },
      { name: 'large body spans bins', targets: [row([0, 0, -30], { radius: 8 }), row([0, 0, -50])] },
      { name: 'equal-distance insertion order', targets: [row([0, 0, -30]), row([0, 0, -30])] },
      { name: 'upward fan bands', forward: [0, .35, -Math.sqrt(1 - .35 ** 2)], targets: [row([0, 12, -30]), row([0, 0, -30])] },
      { name: 'downward fan bands', origin: [0, 20, 0], forward: [0, -.35, -Math.sqrt(1 - .35 ** 2)], targets: [row([0, 8, -30])] });
    if (area === 'line') cases.push(
      { name: 'front and rear budgets', targets: [row([0, 0, -20]), row([0, 0, -40])] },
      { name: 'large front exhausts each zone', targets: [row([0, 0, -20], { radius: 20 }), row([0, 0, -40])] },
      { name: 'out-of-range blocker consumes before honest gate', targets: [row([0, 0, -20], { radius: 20, rangeFactor: .01 }), row([0, 0, -40])] },
      { name: 'obstructed blocker consumes before clearance gate', targets: [row([0, 0, -20], { radius: 20, cut: 0 }), row([0, 0, -40])] },
      { name: 'endpoint cap inside', point: [0, 2, -40], targets: [row([0, 2, -40 - r - .5 + .01])] },
      { name: 'endpoint cap outside', point: [0, 2, -40], targets: [row([0, 2, -40 - r - .5 - .01])] },
      { name: 'side section inside', targets: [row([r + .5 - .01, 2, -30])] },
      { name: 'side section outside', targets: [row([r + .5 + .01, 2, -30])] },
      { name: 'upward 3D section', point: [0, 50, -60], targets: [row([0, 24, -30]), row([r, 24, -30])] },
      { name: 'vertical axis alternate basis', point: [0, 60, 0], targets: [row([0, 20, 0]), row([r + .49, 40, 0])] },
      { name: 'zero-length section', point: [0, 2, 0], targets: [row([0, 2, 0])] });
    if (area === 'blast') cases.push(
      { name: 'shared aim buffer overwrites reticle surface', exact: 1, point: [0, 2, -15], targets: [row([0, 0, -30], { kind: 'base', radius: 15 }), row([0, 0, -30 - def.r * 1.5])] },
      { name: 'terrain impact splash without reticle', point: [0, 2, -30], targets: [row([0, 0, -30]), row([0, 0, -30 - def.r * 1.5])] },
      { name: 'splash behind obstruction ignores clearance', exact: 1, targets: [row([0, 0, -30]), row([1, 0, -30], { cut: 0 })] },
      { name: 'edge surface inside', point: [0, 2, -30], targets: [row([def.r * d.BLAST.EDGE + .5 - .01, 0, -30])] },
      { name: 'edge surface outside', point: [0, 2, -30], targets: [row([def.r * d.BLAST.EDGE + .5 + .01, 0, -30])] },
      { name: 'vertical band above', point: [0, 6, -30], targets: [row([0, 0, -30])] },
      { name: 'whole shot arming warning', exact: 1, point: [0, 2, -3], targets: [row([0, 0, -3]), row([1, 0, -3])] });
    if (d.trajClass(def) === 'lob') cases.push(
      { name: 'cached control impact', control: { on: true, ok: true, close: false, has_impact: true, impact: [0, 2, -30], aim: [0, 2, -100] }, targets: [row([0, 0, -30])] },
      { name: 'cached failed control rejects all', control: { on: true, ok: false, close: false, has_impact: true, impact: [0, 2, -30], aim: [0, 2, -30] }, targets: [row([0, 0, -30])] },
      { name: 'cached close control warns every victim', control: { on: true, ok: true, close: true, has_impact: true, impact: [0, 2, -3], aim: [0, 2, -30] }, targets: [row([0, 0, -3]), row([1, 0, -3])] },
      { name: 'cached absent impact uses aim', control: { on: true, ok: true, close: false, has_impact: false, impact: [0, 2, -100], aim: [0, 2, -30] }, targets: [row([0, 0, -30])] });
    for (const scenario of cases) {
      const origin = V(scenario.origin || [0, 2, 0]), forward = V(scenario.forward || [0, 0, -1]);
      const entries = scenario.targets.map((target, i) => ({ ...target, id: i + 1,
        position: V(target.position).toArray(), reach: reach * (target.rangeFactor || 1),
        visible: target.visible !== false, self: !!target.self, dead: !!target.dead, garrison: !!target.garrison,
        ally: !!target.ally, foe: !target.ally && !target.neutral }));
      const ents = entries.map(t => ({ id: t.id, kind: t.kind, side: t.ally ? 'STEEL' : 'SWARM',
        neutral: !!t.neutral, isSelf: t.self, dead: t.dead, gar: t.garrison,
        dimTop: t.top, dimH: t.height, hr: t.radius, reach: t.reach,
        mesh: { position: V(t.position), visible: t.visible } }));
      for (const ent of ents) entries[ent.id - 1].penetration_cost = d.lancePenCost(ent);
      const point = V(scenario.point || [0, 2, -30]);
      const exact = ents.find(e => e.id === scenario.exact) || null;
      const control = scenario.control ? { ...scenario.control,
        impact: V(scenario.control.impact), aim: V(scenario.control.aim) } : {};
      const ctx = { ...seams, side: 'STEEL', gunGroup: null, camera: { position: origin, getWorldDirection: v => v.copy(forward) },
        ents: new Map(ents.map(e => [e.id, e])), _hitR: e => e.hr, _effRange: (_, e) => e?.reach ?? reach,
        _maxRange: () => reach * d.altRangeMax(def), _shotV0: d.shotV0,
        _lobCrosshair: () => ({ pt: point, ent: exact }), _resolveAim: () => ({ point }),
        _lobFc: control.on ? { ...control, hasImpact: control.has_impact } : null,
        _layerHitT: (ax, ay, az, bx, by, bz) => {
          const target = ents.find(e => V([bx, by, bz]).distanceTo(ctx._entAimPoint(e)) < .0001);
          return target ? entries[target.id - 1].cut ?? null : null;
        } };
      const result = ctx._shotVictims(def, d.reachRule(def));
      shotFootprints.push({ character, slot, level, name: scenario.name, origin: origin.toArray(), forward: forward.toArray(),
        targets: entries, crosshair: { point: point.toArray(), target: exact?.id || 0 },
        control: scenario.control || {}, result: result ? { hits: result.hits.map(e => e.id), warn: result.warn } : {} });
    }
  }
  return { shotFootprints };
}
