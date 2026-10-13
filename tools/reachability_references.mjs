import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

// Evaluate the original advisory seams without loading any source code at runtime.
export async function reachabilityReferences(d, gameSource, source) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n/g, '\n');
  const tolerance = /const RANGE_GLOW = \{ SURF_TOL_M: ([\d.]+) \};/.exec(text);
  if (!tolerance) throw new Error('Missing source reachability clearance tolerance');
  const RANGE_GLOW = { SURF_TOL_M: Number(tolerance[1]) };
  const scope = { THREE, ...d, RANGE_GLOW, ARC_MAXP: Number(/const ARC_MAXP = (\d+);/.exec(text)?.[1]) };
  const method = name => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing source reachability method: ${name}`);
    return new Function(...Object.keys(scope), `return function ${text.slice(start + 1, end + 4).trimStart().slice(name.length)}`)(...Object.values(scope));
  };
  const seams = Object.fromEntries(['_reachable', '_shotWarn', '_lobSolve', '_lobVel', '_lob45Vel', '_arcTrace', '_lobLadder'].map(name => [name, method(name)]));
  const V = p => new THREE.Vector3(...p.map(Math.fround));
  const reachability = [];
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
    const def = d.heroWeapon(character, slot, level), rule = d.reachRule(def);
    const radius = 3, height = 6, reach = def.range;
    const core = d.blastCoreR(def), min = d.lobMinRange(def), arm = d.armingOf(def)?.m || 0;
    const scenarios = [
      { name: 'clear centre', distance: reach * .6 },
      { name: 'surface just inside range', distance: reach + radius - .01 },
      { name: 'surface just outside range', distance: reach + radius + .01 },
      { name: 'expanded altitude envelope', distance: reach * 1.1, range: reach * 1.2 },
      { name: 'wall before target', distance: reach * .6, cut: 1 },
      { name: 'wall within blast core', distance: reach * .6, gap: core + radius - .01 },
      { name: 'wall outside blast core', distance: reach * .6, gap: core + radius + .01 },
      { name: 'clearance tolerance inside', distance: reach * .6, gap: radius + RANGE_GLOW.SURF_TOL_M - .01 },
      { name: 'clearance tolerance outside', distance: reach * .6, gap: radius + RANGE_GLOW.SURF_TOL_M + .01 },
      { name: 'origin inside body', distance: 1 },
      ...(min > 0 ? [{ name: 'minimum range inside', distance: min + radius - .01 }, { name: 'minimum range outside', distance: min + radius + .01 }] : []),
      ...(arm > 0 ? [{ name: 'arming inside', distance: arm + radius - .01 }, { name: 'arming outside', distance: arm + radius + .01 }] : []),
    ];
    if (rule.path === 'arc') scenarios.push(
      { name: 'air target low solution', distance: reach * .6, kind: 'heli', y: 20 },
      { name: 'air charge ladder blocked', distance: reach * .7, kind: 'heli', y: 20, wall: { x: reach * .35, top: 35 } },
      { name: 'no real air solution', distance: 5, kind: 'heli',
        y: d.shotV0(def, true) ** 2 / (2 * d.BALLISTIC.G) + 10,
        range: d.shotV0(def, true) ** 2 / d.BALLISTIC.G * 2 + 50 },
      { name: 'upward envelope rejects', distance: 10, y: reach * 1.2 },
      { name: 'downward envelope', distance: reach * .7, origin: [0, 70, 0] });
    for (const scenario of scenarios) {
      const origin = V(scenario.origin || [0, 2, 0]);
      const point = V([scenario.distance, scenario.y ?? -1, 0]);
      const aim = point.clone().add(V([0, height / 2, 0]));
      const full = origin.distanceTo(aim);
      const rayCut = scenario.cut ?? (scenario.gap != null ? Math.max(0, full - scenario.gap) : null);
      const wall = scenario.wall || (rule.path === 'arc' && rayCut != null ? { x: rayCut, top: 300 } : null);
      const boxes = wall ? [{ min: [wall.x - .5, -20, -30], max: [wall.x + .5, wall.top, 30] }] : [];
      const solids = boxes.map(box => new THREE.Box3(V(box.min), V(box.max)));
      const ground = { base: -20, x: 0, z: 0 };
      const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 20);
      const collision = (a, b) => {
        if (rule.path !== 'arc') return rayCut;
        const direction = b.clone().sub(a), length = direction.length();
        const ray = new THREE.Ray(a, direction.normalize());
        let closest = Infinity;
        for (const p of [ray.intersectPlane(plane, new THREE.Vector3()), ...solids.map(box => ray.intersectBox(box, new THREE.Vector3()))]) {
          if (p) closest = Math.min(closest, a.distanceTo(p));
        }
        return closest <= length ? closest : null;
      };
      const ent = { kind: scenario.kind || 'soldier', dimH: height, dimTop: height, mesh: { position: point } };
      const ctx = { ...seams, gunGroup: null, camera: { position: origin }, _hitR: () => radius,
        _shotV0: d.shotV0, _layerHitT: (ax, ay, az, bx, by, bz) => collision(V([ax, ay, az]), V([bx, by, bz])) };
      const range = scenario.range || reach;
      reachability.push({ character, slot, level, name: scenario.name, origin: origin.toArray(),
        target: { position: point.toArray(), kind: ent.kind, height, radius }, range, rayCut, ground, boxes,
        result: ctx._reachable(ent, def, rule, range) });
    }
  }
  return { reachability, reachabilityRules: RANGE_GLOW };
}
