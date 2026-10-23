import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Execute original spectator methods; native physics owns the supplied pull ray.
export async function spectatorReferences(d, source, gameSource, heroView) {
  const {grabMethod} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n?/g, '\n');
  const names = ['_specRoster', '_specName', '_specFollow', '_specSetView', '_specCycleView', '_specHud', '_updateSpectator', '_cameraPullSegment'];
  const proto = new Function(...Object.keys(d), 'THREE', 'heroView',
    'return ({' + names.map(name => grabMethod(text, name)).join(',\n') + '});')(...Object.values(d), THREE, heroView);
  const number = (pattern, label, body = text) => {
    const match = pattern.exec(body);
    if (!match) throw new Error('Missing original spectator seam: ' + label);
    return Number(match[1]);
  };
  const rules = {camera: d.SPEC_CAM,
    initialFov: number(/const fov = this\.heroKind \? UNITS\[this\.heroKind\]\.fov : ([\d.]+)/, 'initial FOV'),
    farFactor: number(/new THREE\.PerspectiveCamera\(fov,[^\n]+span \* ([\d.]+)\)/, 'far plane span'),
    startHeight: number(/this\.terrain\.heightAt\(cx, cz\) \+ ([\d.]+)/, 'spawn height'),
    startPitch: number(/this\.pitch = (-?[\d.]+);\s*\n\s*this\._specFov/, 'spawn pitch'),
    fovThreshold: number(/Math\.abs\(this\.camera\.fov - this\._specFov\) > ([\d.]+)/, 'FOV update threshold'),
    abilityFallbackCd: number(/cdMax: A\.cd \|\| ([\d.]+)/, 'spectator ability duration'),
    profiles: {}, fallbacks: {}, display: {}, names: {}, sideSuffix: {}, unknownName: proto._specName.call({}, null), ui: {}};
  for (const [ch, c] of Object.entries(d.CHARACTERS)) {
    rules.display[ch] = {code: c.code, machine: c.machine};
    rules.profiles[ch] = {height: d.heroTargetH(c.kind, ch), ground: heroView(c.kind, ch, false), air: heroView(c.kind, ch, true)};
    for (const side of ['', ...Object.keys(d.SIDES)]) rules.names[ch + ':' + side] = proto._specName.call({}, {ch, side, pid: '17'});
  }
  for (const side of ['', ...Object.keys(d.SIDES)]) {
    const kind = (side && d.SIDES[side].hero) || 'robot';
    rules.fallbacks[side] = {height: d.heroTargetH(kind, ''), ground: heroView(kind, '', false), air: heroView(kind, '', true)};
  }
  for (const side of Object.keys(d.SIDES))
    rules.sideSuffix[side] = proto._specName.call({}, {pid: '{pid}', side}).replace('{pid}', '');
  const programs = [];
  const run = (label, initial, operations) => {
    let surface = initial.surface ?? 0, ceiling = initial.ceiling ?? 10000, hit = null;
    const messages = [], entities = new Map();
    const ctx = Object.assign(Object.create(proto), {
      side: null, yaw: 0, pitch: rules.startPitch, keys: {},
      pos: new THREE.Vector3(0, Math.min(rules.startHeight, ceiling), 0),
      camera: {position: new THREE.Vector3(), fov: 68, rotation: {set() {}}, rotateY() {}, rotateX() {}, updateProjectionMatrix() {}},
      _specView: d.SPEC_CAM.VIEWS[0], _specPid: null, _specHid: null,
      _specFov: 68, _specAnchor: new THREE.Vector3(), _specAnchorOk: false, _specYaw: 0,
      ents: entities, hud: {feed: value => messages.push(value)},
      _surf: () => surface, _ceilY: () => ceiling,
      _moveAxis: () => ({f: 0, r: 0, mag: 0, boost: false}),
      _blockerHitT: () => hit,
    });
    const record = () => ({mode: ctx._specView, pid: ctx._specPid ?? '', position: ctx.pos.toArray(),
      camera: ctx.camera.position.toArray(), yaw: ctx.yaw, pitch: ctx.pitch, fov: ctx._specFov, cameraFov: ctx.camera.fov,
      anchor: ctx._specAnchor.toArray(), anchorOk: ctx._specAnchorOk, followYaw: ctx._specYaw,
      hidden: ctx._specHid?.pid ?? '', roster: ctx._specRoster().map(actor => actor.pid),
      visible: Object.fromEntries([...entities.values()].map(actor => [actor.pid, actor.mesh.visible])), messages: [...messages]});
    const steps = [];
    for (const operation of operations) {
      messages.length = 0;
      if (operation.add) {
        const actor = operation.add;
        entities.set(actor.pid, {...actor, mesh: {position: new THREE.Vector3(...actor.position), visible: actor.visible ?? true}});
      }
      if (operation.update) {
        const actor = entities.get(operation.update.pid), {position, ...fields} = operation.update;
        Object.assign(actor, fields);
        if (position) actor.mesh.position.fromArray(position);
      }
      if (operation.remove) entities.delete(operation.remove);
      if (operation.position) ctx.pos.fromArray(operation.position);
      for (const field of ['yaw', 'pitch']) if (operation[field] != null) ctx[field] = operation[field];
      if (operation.surface != null) surface = operation.surface;
      if (operation.ceiling != null) ceiling = operation.ceiling;
      if ('hit' in operation) hit = operation.hit;
      if ('mode' in operation) ctx._specSetView(operation.mode);
      if ('follow' in operation) ctx._specFollow(operation.follow);
      if (operation.cycle) ctx._specCycleView();
      if ('zoom' in operation) {
        // Capture the actual wheel branch rather than a copied zoom equation.
        const start = text.indexOf('        const f = e.deltaY > 0 ? SPEC_CAM.FOV_STEP');
        const end = text.indexOf('        return;', start);
        if (start < 0 || end < start) throw new Error('Missing original spectator wheel branch');
        new Function('e', 'SPEC_CAM', text.slice(start, end)).call(ctx, {deltaY: operation.zoom}, d.SPEC_CAM);
      }
      if ('delta' in operation) {
        ctx._moveAxis = () => operation.axis ?? {f: 0, r: 0, mag: 0, boost: false};
        ctx.keys = {Space: !!operation.up, KeyC: !!operation.down, ControlLeft: !!operation.ctrl};
        ctx._updateSpectator(operation.delta);
      }
      steps.push({operation, result: record()});
    }
    programs.push({label, initial, steps});
    return ctx;
  };
  const ch = Object.keys(d.CHARACTERS)[0];
  const actor = (pid, side, position = [0, 0, 0], extra = {}) => ({pid, side, position, ch, hero: true, act: true, dead: false, ry: 0, heroY: 0, ...extra});
  run('empty roster and invalid view', {}, [{follow: 1}, {mode: 'fpv'}, {mode: 'invalid'}, {cycle: true}, {delta: 0}]);
  run('roster order, stable nearest ties, missing target and pitch transitions', {}, [
    ...[actor('2', 'SWARM', [-1, 0, 0]), actor('10', 'SWARM', [1, 0, 0]), actor('b2', 'STEEL'), actor('b10', 'STEEL'),
      actor('9', 'SWARM', [0, 0, 0], {act: false}), actor('8', 'SWARM', [0, 0, 0], {hero: false}),
      actor('7', 'SWARM', [30, 0, 0], {dead: true, visible: false})].map(add => ({add})),
    {position: [0, 0, 0], follow: 0}, {delta: .016}, {follow: -1}, {delta: .016},
    {mode: 'tps'}, {pitch: .4, mode: 'orbit'}, {mode: 'fpv'}, {delta: 0}, {follow: null},
    {pitch: .3, mode: 'god'}, {follow: 1}, {remove: 'b10'}, {follow: 1},
    {remove: 'b2'}, {delta: .016}, {follow: 1}, {delta: .016},
  ]);
  for (const [character, c] of Object.entries(d.CHARACTERS)) for (const mode of d.SPEC_CAM.VIEWS.slice(1)) {
    for (const height of [0, d.SPEC_CAM.FLY_M, d.SPEC_CAM.FLY_M + .001]) {
      run(character + ':' + mode + ':' + height, {}, [
        {add: actor('17', c.side === 'MERC' ? 'STEEL' : c.side, [12, 5, -20], {ch: character, heroY: height, ry: 3.12})},
        {mode}, {yaw: -3.12, pitch: -.3, delta: 0}, {delta: 1 / 60},
        {update: {pid: '17', position: [15, 6, -20], ry: -3.12}, delta: 1 / 30},
        {update: {pid: '17', position: [15 + d.SPEC_CAM.SNAP_M, 6, -20]}, delta: .016},
        {update: {pid: '17', position: [300, 10, -20]}, delta: .016},
        {zoom: -1, delta: .016}, {update: {pid: '17', dead: true}, mode: 'god', delta: .016},
      ]);
    }
  }
  run('free movement, simultaneous rise/descend, floor before ceiling', {}, [
    {yaw: .7, delta: .1, axis: {f: 1, r: 1, mag: Math.SQRT2, boost: false}},
    {delta: .1, up: true, down: true, axis: {f: -.4, r: .2, mag: Math.sqrt(.2), boost: true}},
    {delta: .1, ctrl: true}, {position: [0, 1, 0], surface: 120, delta: .1, down: true},
    {position: [0, 399.9, 0], ceiling: 400, delta: .1, up: true},
    {surface: 500, ceiling: 100, delta: .1},
    ...Array.from({length: 40}, () => ({zoom: 1, delta: 0})),
    ...Array.from({length: 70}, () => ({zoom: -1, delta: 0})),
  ]);
  run('shared segment pull and follow floor without ceiling clamp', {}, [
    {add: actor('17', 'STEEL', [0, 50, 0])}, {mode: 'tps'}, {hit: 4, delta: .016},
    {mode: 'orbit'}, {hit: null, surface: 120, ceiling: 1, delta: .016},
    {mode: 'fpv', delta: .016}, {remove: '17'}, {delta: .016},
  ]);
  run('recreated target retains identity but restores the old hidden object', {}, [
    {add: actor('17', 'STEEL')}, {mode: 'fpv'}, {delta: .016},
    {add: actor('17', 'STEEL', [40, 5, 0])}, {delta: .016}, {mode: 'tps'}, {delta: .016},
  ]);
  for (const fps of [30, 60, 240]) run('one second orbit convergence at ' + fps + 'fps', {}, [
    {add: actor('17', 'STEEL')}, {mode: 'orbit'}, {delta: 0},
    {update: {pid: '17', position: [20, 0, 0], ry: 1.2}},
    ...Array.from({length: fps}, () => ({delta: 1 / fps})),
  ]);
  for (const side of ['', ...Object.keys(d.SIDES)]) run('snapshot without character: ' + side, {}, [
    {add: actor('17', side, [0, 5, 0], {ch: ''})}, {mode: 'fpv'}, {delta: .016},
    {update: {pid: '17', heroY: d.SPEC_CAM.FLY_M + 1}, delta: .016}, {mode: 'tps'}, {delta: .016},
  ]);
  // Obtain localized templates by executing original notices with a name seam.
  const templateMessages = [];
  const template = Object.assign(Object.create(proto), {_specView: 'god', _specPid: null, pitch: 0,
    _specRoster: () => [], hud: {feed: value => templateMessages.push(value)}});
  template._specFollow(1); rules.ui.noneFollow = templateMessages.pop();
  template._specSetView('fpv'); rules.ui.noneMode = templateMessages.pop();
  template._specSetView('god'); rules.ui.god = templateMessages.pop();
  template._specPid = '17'; template._specRoster = () => [{pid: '17'}]; template._specName = () => '{name}';
  template._specSetView('fpv');
  rules.ui.follow = templateMessages.pop().replace(d.SPEC_CAM.NAMES.fpv, '{view}');
  rules.ui.hudFollow = {};
  for (const character of [ch, '']) {
    template._specRoster = () => [{pid: '17', ch: character}];
    const who = template._specHud().who;
    rules.ui.hudFollow[character ? 'character' : 'unknown'] = who
      .replace(d.CHARACTERS[ch].machine, '{machine}').replace(d.SPEC_CAM.NAMES.fpv, '{view}');
  }
  rules.ui.hudFree = {};
  const spectatorHud = [];
  for (const view of d.SPEC_CAM.VIEWS) {
    const ctx = Object.assign(Object.create(proto), {side: null, _specPid: null, _specView: view, _specRoster: () => []});
    const expected = ctx._specHud();
    rules.ui.hudFree[view] = expected.who;
    spectatorHud.push({view, side: '', actors: [], pid: '', result: expected});
  }
  for (const [ch, c] of Object.entries(d.CHARACTERS)) for (const view of d.SPEC_CAM.VIEWS) for (const tier of [0, 1, 2, 3, 4]) {
    const target = actor('17', c.side === 'MERC' ? 'STEEL' : c.side, [0, 0, 0], {ch, hp: 37, max: 100,
      ab: {light: tier, heavy: tier, def: tier, atk: tier}, mp: tier === 0 ? 0 : 1000, mm: 1500,
      cds: tier % 2 ? [0, 2.5] : [3.5, 0], sp: 14, maxSp: 90, rs: 2, dead: tier === 0,
      up: {lw: tier, hw: tier, def: tier, atk: tier, armor: tier}, money: 71, kn: 13, emp: 4});
    const ctx = Object.assign(Object.create(proto), {side: null, _specPid: target.pid, _specView: view, _specRoster: () => [target]});
    spectatorHud.push({view, side: '', actors: [target], pid: target.pid, result: ctx._specHud()});
    if (tier === 1) {
      ctx.side = target.side;
      spectatorHud.push({view, side: ctx.side, actors: [target], pid: target.pid, result: ctx._specHud()});
    }
  }
  for (const view of d.SPEC_CAM.VIEWS) {
    const target = actor('17', '', [0, 0, 0], {ch: '', hp: 0, max: 1, mp: 0, mm: 0, maxSp: 0});
    const ctx = Object.assign(Object.create(proto), {side: null, _specPid: target.pid, _specView: view, _specRoster: () => [target]});
    spectatorHud.push({view, side: '', actors: [target], pid: target.pid, result: ctx._specHud()});
  }
  return {rules, fixtures: {spectatorPrograms: programs, spectatorHud}};
}
