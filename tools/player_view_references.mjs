import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { viewOcclusionReferences } from './view_occlusion_references.mjs';

// Offline only: execute the original TPS camera, mode notifications and body turn.
export async function playerViewReferences(d, gameSource, source) {
  const { grabMethod, grabBlock } = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n?/g, '\n');
  const control = (await readFile(join(source, 'public/js/ctrlmode.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const compile = (body, scope, result) => new Function(...Object.keys(scope), body + '\nreturn ' + result)(...Object.values(scope));
  const originalMethod = (name, scope = {}) => compile('', { ...d, THREE, ...scope }, `function ${grabMethod(text, name).trimStart().slice(name.length)}`);
  const number = (body, pattern, label) => {
    const match = pattern.exec(body);
    if (!match) throw new Error('Missing original player-view seam: ' + label);
    return Number(match[1]);
  };
  const controlModule = (initial, saved = []) => compile(control.replace(/^export /gm, ''), {
    window: { localStorage: { getItem: key => key === 'svs_view_mode' ? initial : null,
      setItem: (key, value) => { if (key === 'svs_view_mode') saved.push(value); } } },
    navigator: {}, location: { search: '' }, URLSearchParams,
  }, '{VIEW_MODES,VIEW_MODE_KEYS,DEFAULT_VIEW_MODE,viewMode,setViewMode,onViewModeChange}');
  const controls = controlModule(null);
  const update = grabMethod(text, '_updatePlayer');
  const cameraStart = update.indexOf('    const eye = this._eyeH();');
  const marker = "if (this.viewMode === 'tps')";
  const cameraBody = grabBlock(update.slice(cameraStart), marker);
  const fovStart = update.indexOf('    const wantFov = ');
  if (cameraStart < 0 || fovStart < cameraStart) throw new Error('Missing original TPS camera order');
  const ringBody = grabBlock(update.slice(fovStart), marker);
  const tmp = Object.fromEntries(['A', 'B', 'C', 'D'].map(key => ['_TMP_' + key, new THREE.Vector3()]));
  const compose = compile('', { ...d, THREE, ...tmp }, `function() {
    const shP=this.shake[0], shY=this.shake[1], shR=this.shake[2]; ${cameraBody}
  }`);
  const frameRing = compile('', { ...d, ...tmp }, `function() ${ringBody}`);
  const deClip = originalMethod('_cameraDeClip'), pull = originalMethod('_cameraPullSegment');
  const body = originalMethod('_stepThirdPersonBody');
  const reportExpression = /ry: Math\.round\(\(([^\n]+)\) \* 100\) \/ 100/.exec(update)?.[1];
  if (!reportExpression) throw new Error('Missing original body-heading report');
  const reportYaw = compile('', {}, `function() {return ${reportExpression};}`);
  const rules = { modes: controls.VIEW_MODES, modeKeys: controls.VIEW_MODE_KEYS, defaultMode: controls.DEFAULT_VIEW_MODE,
    spawnPitch: number(grabMethod(text, '_placeAt'), /this\.pitch = (-?[\d.]+)/, 'spawn view pitch'),
    bodyMovingSquared: number(body.toString(), /move\.lengthSq\(\) > ([\d.]+)/, 'body input threshold'),
    ringDenominator: number(ringBody, /Math\.abs\(denom\) > ([\de.-]+)/, 'ring singularity'),
    pullHeight: number(deClip.toString(), /this\.selfH \* ([\d.]+) : this\._eyeH/, 'TPS pull height'), colliders: {} };
  const occlusion = await viewOcclusionReferences(gameSource, source);
  rules.occlusion = occlusion.rules;
  const hazardBody = grabBlock(text, "if (hazDef || e.k === 'aasite' || e.k === 'relay')");
  const radiusLine = /const r = [^;]+;/.exec(hazardBody)?.[0];
  const radiusField = /colR: ([^\n]+),\n/.exec(hazardBody)?.[1];
  const heightField = /colH: ([^\n]+),\n/.exec(hazardBody)?.[1];
  if (!radiusLine || !radiusField || !heightField) throw new Error('Missing original view collider construction');
  const collider = compile('', { HAZARDS: d.HAZARDS }, `function(e) {
    const hazDef=HAZARDS[e.k]; ${radiusLine} return {colR:${radiusField},colH:${heightField}};
  }`);
  const collapseText = grabMethod(text, '_applyCollapse');
  rules.collapseHeight = number(collapseText, /ent\.colH = \(ent\.colH \|\| 6\) \* ([\d.]+)/, 'collapsed collider height');
  const collapseStart = collapseText.indexOf('    const rf = '), collapseEnd = collapseText.indexOf('\n    if (!instant)', collapseStart);
  if (collapseStart < 0 || collapseEnd < collapseStart) throw new Error('Missing original collapsed view collider');
  const collapse = compile('', d, `function(ent) {${collapseText.slice(collapseStart, collapseEnd)}}`);
  const collapsedUnit = { colR: 1, colH: 1 }; collapse(collapsedUnit);
  rules.collapseRadius = collapsedUnit.colR;
  const playerViewColliders = [];
  for (const kind of [...Object.keys(d.HAZARDS), 'aasite', 'relay']) {
    const one = collider({ k: kind, sc: 1 }), two = collider({ k: kind, sc: 2 });
    rules.colliders[kind] = { radius: one.colR, height: one.colH, scaleRadius: one.colR !== two.colR };
    for (const scale of [0, .5, 1, 2]) for (const collapsed of [false, true]) {
      const result = collider({ k: kind, sc: scale }); if (collapsed) collapse(result);
      playerViewColliders.push({ kind, scale, collapsed, result });
    }
  }
  const cameraAngleSteps = [];
  for (const current of [-7, -Math.PI, 0, Math.PI, 7]) for (const difference of [-Math.PI * 4, -Math.PI, -.02, 0, .02, Math.PI, Math.PI * 4]) {
    for (const delta of [0, .016, .1]) cameraAngleSteps.push({ current, target: current + difference, rate: d.PLAYER_TPS.BODY_TURN_K, delta,
      result: d.camAngleStep(current, current + difference, d.PLAYER_TPS.BODY_TURN_K, delta) });
  }
  const playerViewBodies = [];
  for (const mode of controls.VIEW_MODE_KEYS) for (const defending of [false, true]) for (const aiming of [false, true]) for (const firing of [false, true]) {
    for (const move of [[0, 0, 0], [.02, 0, 0], [.020001, 0, 0], [-.6, 0, -.8], [0, 0, 1]]) for (const yaw of [0, -3.12, 3.12]) {
      const ctx = { viewMode: mode, defending, aiming, firing, bodyYaw: -3.12, yaw };
      const steps = [];
      for (const delta of [0, .004, .016, .1]) {
        body.call(ctx, delta, new THREE.Vector3(...move)); steps.push({ delta, result: ctx.bodyYaw, report: reportYaw.call(ctx) });
      }
      playerViewBodies.push({ mode, defending, aiming, firing, move, yaw, body_yaw: -3.12, steps });
    }
  }
  const playerViewModes = [];
  for (const initial of [...controls.VIEW_MODE_KEYS, 'invalid', '']) {
    const saved = [], aimEvents = [], module = controlModule(initial, saved);
    const startMode = module.viewMode();
    const ctx = { side: 'STEEL', yaw: .7, bodyYaw: -.4, viewMode: startMode, aiming: false, _aimViewRestore: null,
      cockpit: { visible: startMode === 'fpv' }, dead: false, ents: new Map([[1, { isSelf: true, dead: false, mesh: { visible: startMode === 'tps' } }]]),
      _clearViewOcclusion() {}, hud: { aiming: on => aimEvents.push(on) }, net: { send() {} } };
    const changed = originalMethod('_onViewModeChange', { setViewMode: module.setViewMode });
    const aim = originalMethod('_setAiming', { setViewMode: module.setViewMode });
    module.onViewModeChange(value => changed.call(ctx, value));
    const steps = [];
    for (const step of [{ mode: 'tps' }, { yaw: 2.3 }, { aim: true }, { yaw: -1.7 }, { mode: 'tps' }, { mode: 'fpv' },
      { aim: true }, { aim: false }, { yaw: -2.4 }, { mode: 'fpv' }, { mode: 'invalid' }, { mode: 'fpv' },
      { side: false, aim: true }, { side: true, aim: true }, { mode: 'tps' }, { yaw: .4 }, { aim: false }, { mode: 'tps' }]) {
      saved.length = 0; aimEvents.length = 0;
      if ('yaw' in step) ctx.yaw = step.yaw;
      if ('side' in step) ctx.side = step.side ? 'STEEL' : null;
      if ('mode' in step) module.setViewMode(step.mode);
      if ('aim' in step) aim.call(ctx, step.aim);
      steps.push({ ...step, saved: saved.slice(), aimEvents: aimEvents.slice(), result: { preference: module.viewMode(), mode: ctx.viewMode,
        yaw: ctx.yaw, body_yaw: ctx.bodyYaw, aiming: ctx.aiming, restore: ctx._aimViewRestore || '' } });
    }
    playerViewModes.push({ initial, yaw: .7, body_yaw: -.4, steps });
  }
  const tryFire = grabMethod(text, '_tryFire');
  const fallbackAt = tryFire.lastIndexOf('this._fallbackFromEmptyHeavy('), muzzleAt = tryFire.indexOf('this._selfMuzzle(');
  if (fallbackAt < 0 || muzzleAt < fallbackAt) throw new Error('Original empty-heavy restoration must precede muzzle selection');
  const fallback = originalMethod('_fallbackFromEmptyHeavy');
  const playerViewFireModes = [];
  for (const initial of controls.VIEW_MODE_KEYS) for (const aiming of [false, true]) for (const slot of ['light', 'heavy']) for (const ammo of [.5, 1, 2]) {
    const module = controlModule(initial), ctx = { side: 'STEEL', yaw: .7, bodyYaw: -.4, viewMode: initial, aiming: false, _aimViewRestore: null,
      cockpit: {}, dead: false, ents: new Map(), _clearViewOcclusion() {}, hud: { aiming() {} }, net: { send() {} } };
    const changed = originalMethod('_onViewModeChange', { setViewMode: module.setViewMode });
    ctx._setAiming = originalMethod('_setAiming', { setViewMode: module.setViewMode });
    module.onViewModeChange(value => changed.call(ctx, value));
    if (aiming) ctx._setAiming(true);
    const before = { mode: ctx.viewMode, yaw: ctx.yaw, body_yaw: ctx.bodyYaw, aiming: ctx.aiming, restore: ctx._aimViewRestore || '' };
    fallback.call(ctx, slot, { ammo: ammo - 1 });
    playerViewFireModes.push({ initial, yaw: .7, body_yaw: -.4, slot, ammo, before, result: { mode: ctx.viewMode, yaw: ctx.yaw, body_yaw: ctx.bodyYaw,
      aiming: ctx.aiming, restore: ctx._aimViewRestore || '' } });
  }
  const playerViewHeights = [];
  for (const [character, hero] of Object.entries(d.CHARACTERS)) for (const level of [0, 20, 100]) {
    playerViewHeights.push({ character, level, result: d.heroTargetH(hero.kind, character) * d.superScaleF(level) });
  }
  const place = originalMethod('_placeAt'), flying = originalMethod('_flying'), playerViewPlacements = [];
  for (const kind of ['robot', 'morph', 'drone']) {
    const character = Object.keys(d.CHARACTERS).find(key => d.CHARACTERS[key].kind === kind);
    if (!character) throw new Error('Missing original spawn-view pilot kind: ' + kind);
    for (const direction of [[.4, -.6], [-1, 0], [0, 0]]) {
      const ctx = { pos: new THREE.Vector3(), _surf: () => 20, isDrone: kind === 'drone', isMorph: kind === 'morph',
        yaw: 2, bodyYaw: -1, pitch: 1, roll: .5, charge: 1, _lowG: true, flight: true, baseFov: 0 };
      place.call(ctx, 12, -9, ...direction);
      playerViewPlacements.push({ character, side: d.CHARACTERS[character].side === 'MERC' ? 'STEEL' : d.CHARACTERS[character].side,
        direction, result: { position: ctx.pos.toArray(), yaw: ctx.yaw, body_yaw: ctx.bodyYaw,
        pitch: ctx.pitch, charge: ctx.charge, low_gravity: ctx._lowG, flight: flying.call(ctx) } });
    }
  }
  const playerViewCameras = [];
  const scenarios = [{ name: 'clear' }, { name: 'raised floor', ground: 90 }, { name: 'non-finite surface', ground: null },
    { name: 'cylinder', obstacle: 'circle' }, { name: 'oriented box', obstacle: 'box' }, { name: 'dynamic obstacle', obstacle: 'entity' },
    { name: 'own collider ignored', obstacle: 'self' }, { name: '3D pull', hit: 18 }, { name: 'no team ring', noRing: true }];
  const singularPitch = Math.atan(2 / Math.tan(68 * Math.PI / 360));
  for (const height of [1, ...['t01', 't04'].map(id => d.heroTargetH(d.CHARACTERS[id].kind, id))]) for (const yaw of [0, 3.12]) {
    for (const pitch of [-1.4, -.18, .6, 1.4, singularPitch]) for (const scenario of scenarios) for (const viewport of [[1440, 900], [900, 1440]]) {
      const camera = new THREE.PerspectiveCamera(scenario.noRing ? 25 : 68, viewport[0] / viewport[1], .5, 5000);
      const position = new THREE.Vector3(12, 20, -9), blockers = [], entities = [];
      const ground = scenario.ground === null ? NaN : scenario.ground ?? 0;
      const ctx = { viewMode: 'tps', selfH: height, yaw, pitch, roll: .03, recoil: { p: .08, y: -.04 }, shake: [.01, -.02, .005],
        camera, pos: position, _surf: () => ground, _onDeck: false, _surfHere: 0, _blockersNear: () => blockers,
        _blockerHitT: () => scenario.hit ?? null, _cameraPullSegment: pull, ents: new Map(), cockpit: { visible: true } };
      if (pitch === singularPitch) { ctx.roll = 0; ctx.recoil = { p: 0, y: 0 }; ctx.shake = [0, 0, 0]; }
      let raw, clipped;
      ctx._cameraDeClip = () => {
        camera.updateMatrixWorld(true); raw = camera.matrixWorld.elements.slice();
        const mid = position.clone().lerp(camera.position, .5);
        if (['circle', 'box'].includes(scenario.obstacle)) blockers.push({ x: mid.x, z: mid.z, y: -80, h: 300,
          ...(scenario.obstacle === 'box' ? { hw2: 2, hd2: 5, ry: .7 } : { r: 2 }) });
        if (['entity', 'self'].includes(scenario.obstacle)) {
          entities.push({ position: [mid.x, -80, mid.z], colR: 2, colH: 300, isSelf: scenario.obstacle === 'self' });
          ctx.ents.set(2, { ...entities[0], mesh: { position: new THREE.Vector3(...entities[0].position) } });
        }
        deClip.call(ctx); camera.updateMatrixWorld(true); clipped = camera.matrixWorld.elements.slice();
      };
      compose.call(ctx);
      const mesh = new THREE.Group(), ring = new THREE.Object3D(); ring.userData.teamRing = true; ring.position.y = .18;
      if (!scenario.noRing) mesh.add(ring);
      ctx.ents.clear(); ctx.ents.set(1, { isSelf: true, mesh }); frameRing.call(ctx); camera.updateMatrixWorld(true);
      playerViewCameras.push({ name: scenario.name, position: position.toArray(), height, yaw, pitch, roll: ctx.roll, recoil: [ctx.recoil.p, ctx.recoil.y], shake: ctx.shake,
        ground: Number.isFinite(ground) ? ground : null, hit: scenario.hit ?? null, blockers, entities, ringY: scenario.noRing ? null : position.y + ring.position.y,
        raw, clipped, projection: camera.projectionMatrix.elements.slice(), result: camera.matrixWorld.elements.slice() });
    }
  }
  return { rules, inputs: ['public/js/ctrlmode.js'], fixtures: { cameraAngleSteps, playerViewBodies, playerViewModes, playerViewFireModes, playerViewHeights, playerViewPlacements, playerViewCameras, playerViewColliders, ...occlusion.fixtures } };
}
