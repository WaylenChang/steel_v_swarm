import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

// Execute original client flight methods offline, using its cached Three.js vectors.
export async function projectileReferences(d, gameSource, source) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n/g, '\n');
  const arcPoints = Number(/const ARC_MAXP = (\d+);/.exec(text)?.[1]);
  if (!arcPoints) throw new Error('Missing source arc point budget');
  const env = { THREE, ...d, ARC_MAXP: arcPoints, starburst() {}, stepProjectileFx() {}, raySolid: () => true,
    _TMP_A: new THREE.Vector3(), _TMP_B: new THREE.Vector3(), _TMP_C: new THREE.Vector3(),
    _TMP_D: new THREE.Vector3(), _FWD_Z: new THREE.Vector3(0, 0, 1) };
  const method = (name, overrides = {}) => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing source projectile method: ${name}`);
    const body = text.slice(start + 1, end + 4).trimStart();
    const scope = { ...env, ...overrides };
    return new Function(...Object.keys(scope), `return function ${body.slice(name.length)}`)(...Object.values(scope));
  };
  const update = method('_updateBullets');
  const guidedLaunch = method('_guidedLaunchVel');
  const rolls = [.37, .8];
  let rollIndex = 0;
  const armSpread = method('_armSpread', { Math: Object.assign(Object.create(Math), { random: () => rolls[rollIndex++] }) });
  const V = ([x, y, z]) => new THREE.Vector3(x, y, z);
  const stateOf = b => ({ position: b.pos.toArray(), origin: b.origin.toArray(), velocity: b.vel.toArray(),
    age: b.age, range: b.max, launch_distance: b.launchDist, target: b.homing || 0,
    guide_point: b.guidePt.toArray(), chase: b.chase, last_known: b.homePtSet,
    home_point: [b.hx, b.hy, b.hz], home_radius: b.hr, dud: b.dud });
  const cases = [];
  const launches = [];
  for (const character of Object.keys(d.CHARACTERS)) {
    for (let level = 1; level <= 4; level++) {
      const def = d.heroWeapon(character, 'heavy', level), trajectory = d.trajClass(def);
      if (!['guide', 'fnf'].includes(trajectory)) continue;
      for (const height of [2, 39, 80]) {
        for (const direction of [[0, 0, -1], [0, 1, 0], [.3, -.2, -.9]]) {
          for (const antiAir of def.type === 'launcher' ? [false, true] : [false]) {
            const ctx = { _surf: () => 0 };
            const dir = V(direction).normalize(), arm = d.armingOf(def);
            // Spread uses two explicit rolls rather than relying on global Math.random state.
            rollIndex = 0;
            const from = V([0, height, 0]);
            const speed = d.shotV0(def, antiAir);
            const fdir = armSpread.call(ctx, dir, arm.spread);
            const launch = guidedLaunch.call(ctx, from, fdir, def, speed);
            launches.push({ character, level, antiAir, origin: from.toArray(), direction: dir.toArray(), rolls,
              velocity: (launch?.vel || fdir.multiplyScalar(speed)).toArray(), distance: launch?.dist || 0 });
          }
        }
      }
      const scenarios = [
        { name: 'unlocked gravity', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], guide: false },
        { name: 'frozen guide point', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)] },
        { name: 'climb before guidance', origin: [0, 2, 0], velocity: [0, 30, -d.shotV0(def)], climb: true },
        { name: 'moving target outside launch range', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], target: true },
        { name: 'lost target uses last known point', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], target: true, lose: 5 },
        { name: 'unarmed swept proximity', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], near: true },
        { name: 'collision beats same-frame range', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], max: 1, hit: 0 },
        { name: 'range disarms before later collision', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], max: 1, hit: 2 },
        { name: 'fuel expiry without collision', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], max: 1, fuel: .1 },
        { name: 'fuel boundary collision wins', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def)], target: true, fuel: .05, hit: 0 },
      ];
      if (def.type === 'launcher') {
        scenarios.push(
          { name: 'AA fixed guide point', origin: [0, 80, 0], velocity: [0, 0, -d.shotV0(def, true)], antiAir: true },
          { name: 'AA guidance after climb distance', origin: [0, 2, 0], velocity: [0, 0, -d.shotV0(def, true)], antiAir: true, climb: true });
      }
      for (const scenario of scenarios) {
        if (trajectory === 'guide' && (scenario.target || scenario.guide === false)) continue;
        const origin = V(scenario.origin);
        const guidePt = origin.clone().add(V([20, 5, -120]));
        if (scenario.near) guidePt.copy(origin).add(V([0, 0, -2]));
        const b = { slot: 'heavy', aoe: true, pierce: false, r: def.r, core: d.blastCoreR(def),
          pos: origin.clone(), origin: origin.clone(), vel: V(scenario.velocity), mv: d.shotV0(def, scenario.antiAir),
          max: scenario.max ?? def.range, launchDist: scenario.climb ? d.guidedLaunchDist(def) : 0,
          guide: scenario.guide !== false && trajectory === 'guide', guidePt,
          homing: scenario.target || (scenario.near && trajectory === 'fnf') ? 1 : null,
          arm: d.armingOf(def).m, fnf: trajectory === 'fnf', fuel: scenario.fuel ?? d.chaseCapS(def),
          age: 0, chase: false, homePtSet: false, hx: 0, hy: 0, hz: 0, hr: 0, dud: false,
          mesh: { position: new THREE.Vector3(), quaternion: { setFromUnitVectors() {} } } };
        const target = { id: 1, mesh: { position: guidePt.clone() } };
        const bursts = [];
        let frame = 0;
        const ctx = { bullets: [b], ents: new Map(b.homing ? [[1, target]] : []), wdef: { heavy: def },
          hud: { feed() {} }, terrain: { heightAt: () => 0 }, net: { send: m => bursts.push(m) },
          _terrainHitT: () => scenario.hit === frame ? .5 : null,
          _rayCandidates() {}, _obstHitT: () => null, _hitR: () => .9,
          _dropBullet() {}, _explosion() {}, _applyBlast() {}, _spinCyclone() {} };
        const steps = [];
        for (; frame < 24 && ctx.bullets.length; frame++) {
          if (scenario.lose === frame) ctx.ents.clear();
          if (scenario.target) target.mesh.position.x += 3;
          const before = stateOf(b);
          const targetData = ctx.ents.has(1) ? { position: target.mesh.position.toArray(), radius: .9 } : {};
          const physicalHit = scenario.hit === frame;
          update.call(ctx, .05);
          steps.push({ before, target: targetData, physicalHit, after: stateOf(b),
            done: !ctx.bullets.length, burst: bursts.length > 0 });
        }
        cases.push({ character, level, antiAir: !!scenario.antiAir, name: scenario.name, delta: .05, fuel: b.fuel, steps });
      }
    }
  }
  const lobMethods = Object.fromEntries(['_lobSolve', '_lobVel', '_lob45Vel', '_arcTrace', '_lobLadder', '_lobAim', '_updateAaMode'].map(name => [name, method(name)]));
  const lobControl = [], lobFlight = [];
  for (const character of Object.keys(d.CHARACTERS)) {
    for (let level = 1; level <= 4; level++) {
      const def = d.heroWeapon(character, 'heavy', level);
      if (d.trajClass(def) !== 'lob') continue;
      const R = def.range;
      const scenarios = [
        { name: 'near ground', aim: [R * .1, 0, 0] },
        { name: 'middle ground', aim: [R * .6, 0, 0], flight: true },
        { name: 'inside honest boundary', aim: [R * .995, 0, 0], flight: true },
        { name: 'outside honest boundary clamps to ground', aim: [R * 1.3, 0, 0], flight: true },
        { name: 'downhill clamp', aim: [R * 1.5, -R * .3, 0], ground: { x: -.2 }, flight: true },
        { name: 'uphill clamp', aim: [R * 1.5, R * .3, 0], ground: { x: .2 } },
        { name: 'diagonal slope clamp', aim: [R, R * .15, R], ground: { x: .1, z: .05 } },
        { name: 'no unsafe vertical clamp', aim: [0, R * 2, 0] },
        { name: 'no unsafe ground clamp', aim: [0, -R * 2, 0], origin: [0, 80, 0] },
        { name: 'too close splash warning', aim: [d.lobMinRange(def) * .5, 0, 0], flight: true },
        { name: '45 degree blocked keeps fixed launch', aim: [R * .8, 0, 0], wall: { x: R * .35, top: 80 } },
        { name: '45 degree clears low ridge', aim: [R * .8, 0, 0], wall: { x: R * .35, top: 5 } },
        { name: 'steep aim falls back to low solution', aim: [20, 30, 0] },
        { name: 'physical range has no solution', aim: [2000, 2000, 0] },
        { name: 'air target alone selects AA', aim: [R * .6, 20, 0], target: 'heli', flight: true },
        { name: 'ground robot does not select AA', aim: [R * .6, 0, 0], target: 'robot' },
        { name: 'air high speed charge ladder', aim: [R * .8, 20, 0], target: 'heli', wall: { x: R * .35, top: 12 } },
        { name: 'air forced to lower charge', aim: [R * .8, 20, 0], target: 'heli', wall: { x: R * .35, top: 30 } },
        { name: 'air obstructed at every charge', aim: [R * .8, 20, 0], target: 'heli', wall: { x: R * .35, top: 100 } },
        { name: 'air beyond range stays unclamped', aim: [R * 2, 30, 0], target: 'heli' },
        { name: 'smaller effective envelope', aim: [R * .9, 0, 0], rangeFactor: .85 },
        { name: 'altitude effective envelope', aim: [R * 1.1, 0, 0], rangeFactor: 1.15 },
      ];
      for (const scenario of scenarios) {
        const origin = V(scenario.origin || [0, 2, 0]), requested = V(scenario.aim);
        const ground = { base: 0, x: 0, z: 0, ...scenario.ground };
        const boxes = scenario.wall ? [{ min: [scenario.wall.x - .5, -20, -30], max: [scenario.wall.x + .5, scenario.wall.top, 30] }] : [];
        const plane = new THREE.Plane(V([-ground.x, 1, -ground.z]).normalize(), -ground.base / Math.hypot(ground.x, 1, ground.z));
        const solids = boxes.map(box => new THREE.Box3(V(box.min), V(box.max)));
        const layerHit = (from, to, extra = 0) => {
          const direction = to.clone().sub(from), distance = direction.length();
          const ray = new THREE.Ray(from, direction.normalize());
          let nearest = Infinity;
          for (const point of [ray.intersectPlane(plane, new THREE.Vector3()), ...solids.map(box => ray.intersectBox(box, new THREE.Vector3()))]) {
            if (point) nearest = Math.min(nearest, from.distanceTo(point));
          }
          return nearest <= distance + extra ? nearest : null;
        };
        const target = scenario.target ? { kind: scenario.target, dead: false, mesh: { position: requested.clone(), visible: true }, dimTop: 3, dimH: 3 } : null;
        const range = R * (scenario.rangeFactor || 1);
        const ctx = { ...lobMethods, side: 'SWARM', ch: character, dead: false, shopOpen: false, gunGroup: {},
          hud: { feed() {} }, camera: { getWorldDirection: dir => dir.set(1, 0, 0) },
          terrain: { heightAt: (x, z) => ground.base + ground.x * x + ground.z * z },
          _curWeapon: () => ({ id: 'heavy', def }), _lobCrosshair: () => ({ from: origin, pt: requested, ent: target }),
          _shotV0: d.shotV0, _effRange: () => range, _ensureArcGuide() {},
          _arcGuide: { arr: new Float32Array(arcPoints * 3), ld: new Float32Array(arcPoints), maxp: arcPoints },
          _layerHitT: (ax, ay, az, bx, by, bz) => layerHit(V([ax, ay, az]), V([bx, by, bz])) };
        ctx._updateAaMode();
        ctx._lobAim();
        const fc = ctx._lobFc;
        const expected = { aim: fc.aim.toArray(), velocity: fc.vel.toArray(), speed: fc.v0, ok: fc.ok,
          aa: fc.aa, high: fc.high, close: fc.close, clamped: fc.cut, hasImpact: fc.hasImpact,
          impact: fc.hasImpact ? fc.impact.toArray() : null, points: Array.from({ length: fc.n }, (_, i) => Array.from(ctx._arcGuide.arr.slice(i * 3, i * 3 + 3))) };
        lobControl.push({ character, level, name: scenario.name, origin: origin.toArray(), aim: requested.toArray(),
          range, target: scenario.target || '', ground, boxes, expected });
        if (scenario.flight) {
          const b = { slot: 'heavy', aoe: true, pierce: false, r: def.r, core: d.blastCoreR(def),
            pos: origin.clone(), origin: origin.clone(), vel: fc.vel.clone(), mv: fc.v0, max: fc.max,
            launchDist: 0, guide: false, guidePt: new THREE.Vector3(), homing: null, arm: 0,
            fnf: false, fuel: d.chaseCapS(def), age: 0, chase: false, homePtSet: false,
            hx: 0, hy: 0, hz: 0, hr: 0, dud: false,
            mesh: { position: new THREE.Vector3(), quaternion: { setFromUnitVectors() {} } } };
          const bursts = [];
          Object.assign(ctx, { bullets: [b], ents: new Map(), wdef: { heavy: def }, net: { send: m => bursts.push(m) },
            _terrainHitT: (from, dir, far) => layerHit(from, from.clone().addScaledVector(dir, far)),
            _rayCandidates() {}, _obstHitT: () => null, _dropBullet() {}, _explosion() {}, _applyBlast() {} });
          let frames = 0;
          while (ctx.bullets.length && frames < 4000) { update.call(ctx, 1 / 60); frames++; }
          if (ctx.bullets.length) throw new Error(`Source lob flight did not terminate: ${character} ${scenario.name}`);
          lobFlight.push({ character, level, name: scenario.name, origin: origin.toArray(), velocity: fc.vel.toArray(),
            range, ground, boxes, frames, state: stateOf(b), burst: bursts[0] || null });
        }
      }
    }
  }
  const kineticFlight = [];
  const hitRange = method('_inHitRange');
  for (const character of Object.keys(d.CHARACTERS)) {
    for (const slot of ['light', 'heavy']) {
      for (let level = 1; level <= 4; level++) {
        const def = d.heroWeapon(character, slot, level);
        if (d.trajClass(def) !== 'flat') continue;
        const speed = d.shotV0(def), step = speed / 60;
        const boundary = Math.ceil(def.range / step) * step + .3;
        const scenarios = [
          { name: 'radial range termination' },
          { name: 'downward ground collision', origin: [0, 2, 0], direction: [0, -.2, -Math.sqrt(.96)] },
          { name: 'upward radial boundary', origin: [0, 2, 0], direction: [0, .5, -Math.sqrt(.75)] },
          { name: 'thin wall swept collision', boxes: [{ min: [-10, 70, -10.5], max: [10, 90, -10] }] },
          { name: 'front body', bodies: [20] },
          { name: 'front and rear bodies', bodies: [20, 40] },
          { name: 'collision before same-frame range', bodies: [boundary + d.hitR({ kind: 'soldier' }) - .05] },
          { name: 'no body past final sweep', bodies: [boundary + d.hitR({ kind: 'soldier' }) + .05] },
          { name: 'overshooting collision rejects out-of-range damage', delta: 1, bodies: [def.range * 1.4] },
        ];
        for (const scenario of scenarios) {
          const origin = V(scenario.origin || [0, 80, 0]);
          const direction = V(scenario.direction || [0, 0, -1]).normalize();
          const boxes = scenario.boxes || [];
          const worldBoxes = boxes.map(box => new THREE.Box3(V(box.min), V(box.max)));
          const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
          const bodies = (scenario.bodies || []).map((distance, index) => ({ id: index + 2,
            position: [0, 80, Math.fround(-distance)], size: [d.hitR({ kind: 'soldier' }) * 2, 4, 2 * d.hitR({ kind: 'soldier' })] }));
          const meshes = bodies.map(body => {
            const mesh = new THREE.Mesh(new THREE.BoxGeometry(...body.size), new THREE.MeshBasicMaterial());
            mesh.position.copy(V(body.position));
            mesh.userData.kind = 'soldier';
            mesh.userData.entity = { id: body.id, kind: 'soldier', side: 'SWARM', mesh };
            mesh.updateMatrixWorld();
            return mesh;
          });
          const reports = [];
          const b = { slot, aoe: false, pierce: d.aoeClass(def) === 'line', r: 0, core: 0,
            pos: origin.clone(), origin: origin.clone(), vel: direction.clone().multiplyScalar(speed), mv: speed,
            max: def.range, launchDist: 0, guide: false, guidePt: new THREE.Vector3(), homing: null,
            arm: 0, fnf: false, fuel: d.chaseCapS(def), age: 0, chase: false, homePtSet: false,
            hx: 0, hy: 0, hz: 0, hr: 0, dud: false, oy: origin.y,
            mesh: { position: new THREE.Vector3(), quaternion: { setFromUnitVectors() {} } } };
          const ctx = { bullets: [b], ents: new Map(), wdef: { [slot]: def }, side: 'STEEL', hud: { feed() {} },
            raycaster: new THREE.Raycaster(), _rayCandidates: (_from, _dir, _far, out) => out.push(...meshes),
            _terrainHitT: (from, dir, far) => {
              const ray = new THREE.Ray(from, dir);
              let closest = Infinity;
              for (const point of [ray.intersectPlane(plane, new THREE.Vector3()), ...worldBoxes.map(box => ray.intersectBox(box, new THREE.Vector3()))]) {
                if (point) closest = Math.min(closest, from.distanceTo(point));
              }
              return closest <= far ? closest : null;
            },
            _obstHitT: () => null, _entByMesh: mesh => mesh.userData.entity,
            _inHitRange: hitRange, _effRange: () => def.range, _hitR: target => d.hitR(target),
            _dropBullet() {}, _hitFeedback() {}, _lanceVisual() {}, _lanceFeedback() {},
            _sendLance: (from, to) => { reports.push({ t: 'lance', origin: from.toArray(), point: to.toArray() }); return []; },
            net: { send: report => reports.push(report) } };
          const delta = scenario.delta || 1 / 60;
          let frames = 0;
          while (ctx.bullets.length && frames < 4000) { update.call(ctx, delta); frames++; }
          if (ctx.bullets.length) throw new Error('Source kinetic flight did not terminate');
          kineticFlight.push({ character, slot, level, name: scenario.name, origin: origin.toArray(), velocity: direction.multiplyScalar(speed).toArray(),
            delta, frames, ground: { base: 0, x: 0, z: 0 }, boxes, bodies, state: stateOf(b), report: reports[0] || null });
          for (const mesh of meshes) { mesh.geometry.dispose(); mesh.material.dispose(); }
        }
      }
    }
  }
  return { projectileLaunches: launches, projectileFlight: cases, lobControl, lobFlight, kineticFlight };
}
