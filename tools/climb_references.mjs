import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function climbReferences(d, source, gameSource) {
  const {grabMethod, grabFn} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = (await readFile(join(source, 'public/js/climb.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const game = gameSource.replace(/\r\n?/g, '\n');
  const start = text.indexOf('export const CLIMB = {');
  const end = text.indexOf('// 3D 幾何(純表現層)');
  if (start < 0 || end <= start) throw new Error('Missing original climb planner/index span');
  const maximumRadius = d.selfCollider(d.SOLDIER_H * Math.max(...Object.values(d.HERO_SIZE).map(value => value.mul[1])), false).r;
  const core = new Function('MAX_BODY_R', 'SLOPE', 'slopeDeg', text.slice(start, end).replace(/^export /gm, '') +
    '\nreturn {CLIMB,CLIMB_ARROW,CLIMB_LABEL,makeClimbIndex,planClimbRoutes};')(maximumRadius, d.SLOPE, d.slopeDeg);
  const step = grabMethod(game, '_stepClimb');
  const index = grabFn(text, 'makeClimbIndex');
  const number = (pattern, code = step) => {
    const match = pattern.exec(code);
    if (!match) throw new Error('Missing original climb scalar: ' + pattern);
    return Number(match[1]);
  };
  const rules = {constants: core.CLIMB, arrows: core.CLIMB_ARROW,
    cell: number(/const CELL = (\d+)/, index), keyStride: number(/i \* (\d+) \+ j/, index),
    lowerTolerance: number(/y < r\.y0 - ([\d.]+)/, index),
    breakRadius: number(/CLIMB.GRAB_R \* ([\d.]+)/), breakBelow: number(/this.pos.y < r.y0 - ([\d.]+)/),
    breakAbove: number(/this.pos.y > r.y1 \+ ([\d.]+)/), intentRadius: number(/if \(gl > ([\d.]+)/),
    intentThreshold: number(/ax.f <= ([\d.]+)/), defaultJump: number(/u\?\.jump \|\| ([\d.]+)/),
    kickHeight: number(/\* ([\d.]+);\n\s+this._climb = null/),
    kickOff: number(/_climbOff = now \+ ([\d.]+)/),
    topOff: number(/this.pos.set\(r.tx[^\n]+\n\s+this._climb = null; this._climbOff = now \+ ([\d.]+)/),
    bottomOff: number(/this.pos.set\(r.bx[^\n]+\n\s+this._climb = null; this._climbOff = now \+ ([\d.]+)/),
    stickResponse: number(/const k = lerpFPS\(([\d.]+)/), friction: number(/const fr6 = frictionFPS\(([\d.]+)/),
    rollResponse: number(/this.roll \+= [^\n]+lerpFPS\(([\d.]+)/), notices: {}};
  const arrowSource = grabFn(text, 'buildClimbArrows');
  rules.arrows.scaleMinimum = number(/const sc = ([\d.]+)/, arrowSource);
  rules.arrows.scaleRange = number(/const sc = [\d.]+ \+ ([\d.]+)/, arrowSource);
  const bankMatch = /this\.roll \+= \(-lat \/ spd \* ([\d.]+) - this\.roll\) \* lerpFPS\(([\d.]+), dt\)/.exec(game);
  if (!bankMatch) throw new Error('Missing original airborne camera bank');
  rules.bankAmount = Number(bankMatch[1]);
  rules.bankResponse = Number(bankMatch[2]);
  const groundRollMatch = /this\.roll \+= \(0 - this\.roll\) \* lerpFPS\(([\d.]+), dt\)/.exec(grabMethod(game, '_updatePlayer'));
  if (!groundRollMatch) throw new Error('Missing original ground camera roll');
  rules.groundRollResponse = Number(groundRollMatch[1]);
  const originalRoll = new Function('roll', 'lat', 'spd', 'dt', 'lerpFPS', bankMatch[0].replace(/this\.roll/g, 'roll') + '; return roll;');
  const groundRoll = new Function('roll', 'dt', 'lerpFPS', groundRollMatch[0].replace(/this\.roll/g, 'roll') + '; return roll;');
  const climbRoll = [];
  for (const current of [-.4, 0, .7]) for (const lateral of [-20, 0, 30]) for (const delta of [0, .016, .5, 2]) for (const flying of [false, true])
    climbRoll.push({current, lateral, speed: 20, delta, flying,
      result: flying ? originalRoll(current, lateral, 20, delta, d.lerpFPS) : groundRoll(current, delta, d.lerpFPS)});
  const compile = new Function('CLIMB', 'CLIMB_LABEL', 'lerpFPS', 'frictionFPS', 'return class Original {' + step + '}');
  const Original = compile(core.CLIMB, core.CLIMB_LABEL, d.lerpFPS, d.frictionFPS);
  const route = (id, kind, x = 0, z = 0) => ({id, kind, x, z, y0: 0, y1: 20, nx: 1, nz: 0,
    bx: x, bz: z, tx: x - 2, tz: z, vy0: 0, vy1: 19.5, fx: x - core.CLIMB.OFF, fz: z, gap: 0, arm: 0});
  const climbQueries = [];
  for (const list of [[], [route(1, 'ladder')], [route(1, 'ladder'), route(2, 'rope')],
    [route(1, 'holds', -32, -32), route(2, 'ladder', 32, 0)]]) {
    const query = core.makeClimbIndex(list);
    for (const x of [-35.2, -32, -28.7999, -3.2001, -3.2, 0, 3.2, 3.2001, 32])
      for (const z of [-32, 0]) for (const y of [-1.0001, -1, 0, 20, 24, 24.0001])
        climbQueries.push({routes: list, point: [x, y, z], id: query(x, z, y)?.id ?? 0});
  }
  const climbPrograms = [];
  for (const kind of ['ladder', 'holds', 'rope']) for (const program of ['ascend', 'descend', 'kick', 'intent', 'break', 'status', 'missing']) {
    const r = route(1, kind), messages = [], client = new Original();
    Object.assign(client, {pos: {x: program === 'intent' ? rules.intentRadius : 1.5, y: program === 'descend' ? 20 : 0, z: 0, set(x, y, z) {Object.assign(this, {x, y, z});}},
      vel: {x: 3, y: 1, z: 2}, vy: -2, charge: .7, _lowG: true, roll: .3, dead: false, keys: {Space: false},
      terrain: {climbAt: core.makeClimbIndex([r])}, _flying: () => false, _ccMoveF: () => cc, _modF: () => speed,
      hud: {feed: value => messages.push(value)}});
    let cc = 1, speed = 1;
    const initial = {x: client.pos.x, y: client.pos.y, z: client.pos.z, impulse_x: 3, impulse_z: 2, vertical: -2, charge: .7, low_gravity: true, roll: .3};
    const steps = [];
    for (let i = 0; i < 8; i++) {
      const now = 10 + i * .25, delta = i === 2 ? 0 : i === 7 ? 2 : .25;
      const forward = program === 'descend' ? -1 : program === 'intent' ? (i < 2 ? .25 : .250001) : 1;
      client.keys.Space = program === 'kick' && i === 1;
      if (program === 'break' && i === 2) client.pos.x = core.CLIMB.GRAB_R * 2 + .0001;
      if (program === 'missing' && i === 2) client.terrain.climbAt = null;
      client.dead = program === 'status' && i === 5;
      const flying = program === 'status' && i === 6;
      client._flying = () => flying;
      cc = program === 'status' && i < 2 ? 0 : .6;
      speed = i === 4 ? 1.4 : 1;
      const jumpSpeed = program === 'kick' && i === 1 ? 0 : 8;
      const input = {forward, move_x: program === 'intent' && i < 3 ? 0 : -1, move_z: 0, jump: client.keys.Space, jump_speed: jumpSpeed,
        cc, speed, flying, dead: client.dead, available: !!client.terrain.climbAt};
      const takeover = client._stepClimb(delta, now, {x: input.move_x, z: 0}, {f: forward}, {jump: jumpSpeed});
      const notices = messages.splice(0);
      if (notices.length) rules.notices[kind] = notices[0];
      steps.push({now, delta, input, teleport: program === 'break' && i === 2 ? client.pos.x : null,
        result: {state: {x: client.pos.x, y: client.pos.y, z: client.pos.z, impulse_x: client.vel.x, impulse_z: client.vel.z,
          vertical: client.vy, charge: client.charge, low_gravity: client._lowG, roll: client.roll},
        takeover, route: client._climb?.id ?? 0, off: client._climbOff || 0, notices}});
    }
    climbPrograms.push({kind, program, route: r, initial, steps});
  }
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const arrows = new Function('THREE', 'CLIMB_ARROW', 'UNIT', 'markShared', arrowSource + '\nreturn buildClimbArrows;')(THREE, core.CLIMB_ARROW, {}, value => value);
  const climbArrows = [];
  for (const list of [[], [route(1, 'ladder')], [route(1, 'holds', -4, 10), {...route(2, 'rope', 12, -10), nx: 0, nz: -1}]]) {
    const root = new THREE.Group(); arrows(root, list);
    const geometry = root.children[0]?.geometry;
    const frames = [];
    for (const delta of [0, .1, 1.25, 4.2, 0, 20]) {
      root.userData.update?.(delta);
      frames.push({delta, batches: root.children.map(node => Array.from({length: node.count}, (_, i) => {
        const matrix = new THREE.Matrix4(); node.getMatrixAt(i, matrix); return matrix.toArray();
      }))});
    }
    climbArrows.push({routes: list, geometry: geometry ? {positions: Array.from(geometry.attributes.position.array), indices: Array.from(geometry.index.array)} : null, frames});
    root.traverse(node => {node.geometry?.dispose();node.material?.dispose();});
  }
  const biomes = (await readFile(join(source, 'public/js/biomes.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const clearStart = biomes.indexOf('    let removed = false;', biomes.indexOf('group.userData.clearAround ='));
  const clearEnd = biomes.indexOf('    return removed;', clearStart);
  if (clearStart < 0 || clearEnd < clearStart) throw new Error('Missing original camp climb clearance');
  const clear = new Function('group', 'climbs', 'clearedKeys', 'wx', 'wz', 'r',
    biomes.slice(clearStart, clearEnd) + '\nreturn climbs.map(route => route.id);');
  const climbClearance = [];
  const radius = d.THIRD.BLD_CLEAR_R;
  for (const camp of [{x: 0, z: 0}, {x: 11, z: -31}]) for (const keys of [[], ['owned']]) {
    const blockers = [
      {x: camp.x, z: -camp.z, r: 2, bld: 1},
      {x: camp.x + radius + 2, z: -camp.z, r: 2, bld: 1},
      {x: camp.x + radius + 1.999, z: -camp.z, r: 2, bld: 1},
      {x: camp.x, z: -camp.z, r: 2},
      {x: camp.x, z: -camp.z, r: 2, bld: 1, osm: 1},
      {x: camp.x, z: -camp.z, r: 2, bld: 1, buildingKey: 'owned'},
      {x: camp.x, z: -camp.z, r: 2, bld: 1, buildingKey: 'retained'}];
    const original = blockers.map((b, i) => ({id: i + 1, b}));
    original.push({id: 8, b: blockers[3], link: blockers[0]}, {id: 9, b: blockers[3], link: blockers[4]});
    const routes = original.map(({id, b, link}) => ({id, blocker: {...b}, ...(link ? {link: {...link}} : {})}));
    const ids = clear({userData: {blockers: blockers.slice()}}, original.slice(), new Set(keys), camp.x, -camp.z, radius);
    climbClearance.push({routes, camps: [camp], buildings: Object.fromEntries(keys.map(key => [key, true])), ids});
  }
  return {rules, inputs: ['public/js/climb.js', 'public/js/biomes.js'], fixtures: {climbQueries, climbPrograms, climbArrows, climbClearance, climbRoll}};
}
