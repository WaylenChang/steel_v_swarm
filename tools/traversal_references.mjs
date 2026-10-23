import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function traversalReferences(d, source, gameSource) {
  const {grabMethod, grabBlock} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = gameSource.replace(/\r\n?/g, '\n');
  const alongSource = grabMethod(text, '_slopeDegAlong');
  const speedSource = grabMethod(text, '_slopeMoveF');
  const epsilon = /run < ([\de.-]+)/.exec(alongSource);
  const speedEpsilon = /m < ([\de.-]+)/.exec(speedSource);
  const deckMargin = /t\.deckMargin \|\| ([\d.]+)/.exec(alongSource);
  const deckTolerance = /- d\) < ([\d.]+)/.exec(alongSource);
  const groundStart = text.indexOf('      const stepDrop =', text.indexOf('\n  _updatePlayer('));
  const groundEnd = text.indexOf('      // Paralyze / freeze', groundStart);
  if (!epsilon || !speedEpsilon || !deckMargin || !deckTolerance || groundStart < 0 || groundEnd <= groundStart)
    throw new Error('Missing original slope traversal seams');
  const snapSource = text.slice(groundStart, groundEnd);
  const warningHead = /if \(slopeStop[^\n]*\{/.exec(text);
  const warningInitial = /this\._slopeWarnAt = ([\d.]+);/.exec(text);
  const warningInterval = /now - this\._slopeWarnAt > ([\d.]+)/.exec(warningHead?.[0] || '');
  const warningBody = warningHead ? grabBlock(text, warningHead[0]) : '';
  const warningText = /this\.hud\.feed\?\.\('([^']+)'\)/.exec(warningBody);
  if (!warningHead || !warningInitial || !warningInterval || !warningText) throw new Error('Missing original steep-slope notice seam');
  const groundTolerance = /this\.pos\.y <= gy \+ ([\d.]+)/.exec(snapSource);
  if (!groundTolerance) throw new Error('Missing original walking support tolerance');
  const routeStart = text.indexOf('      if (!passable(this.pos.x, this.pos.z) && passable(px0, pz0))');
  const routeBody = routeStart < 0 ? '' : grabBlock(text, '      if (!passable(this.pos.x, this.pos.z) && passable(px0, pz0))');
  const routeEnd = routeBody.indexOf('        const gy2 =');
  if (routeStart < 0 || routeEnd < 0) throw new Error('Missing original uphill axis-slide seam');
  const scope = {...d};
  const create = code => new Function(...Object.keys(scope), code)(...Object.values(scope));
  const Original = create('return class Original {' + alongSource + speedSource + '}');
  const warn = create('return function(now,slopeStop,px0,pz0) {' + warningHead[0].slice(0, -1) + warningBody + '}');
  const snap = create(`return function(px0,pz0,py0,gyS) { const gy=gyS; ${snapSource}\nreturn {onGround,position:this.pos.y,vertical:this.vy}; }`);
  const slide = create(`return function(px0,pz0,py0,passable) {
    if (!passable(this.pos.x,this.pos.z) && passable(px0,pz0)) {
      ${routeBody.slice(1, routeEnd)}
    }
    return {position:[this.pos.x,this.pos.y,this.pos.z],impulse:[this.vel.x,this.vel.z]};
  }`);
  const rules = {epsilon: Number(epsilon[1]), speedEpsilon: Number(speedEpsilon[1]), deckMargin: Number(deckMargin[1]), deckTolerance: Number(deckTolerance[1]), groundTolerance: Number(groundTolerance[1]),
    warningInitial: Number(warningInitial[1]), warningInterval: Number(warningInterval[1]), warningText: warningText[1]};
  const traversalMath = [];
  for (const angle of [-89, -d.SLOPE.SNAP_DEG, -d.SLOPE.BLOCK_DEG, -d.SLOPE.EASE_DEG, 0,
    d.SLOPE.EASE_DEG, d.SLOPE.EASE_DEG + 1e-6, d.SLOPE.BLOCK_DEG - 1e-6, d.SLOPE.BLOCK_DEG, d.SLOPE.BLOCK_DEG + 1e-6, 89])
    traversalMath.push({angle, factor: d.slopeMoveF(angle), blocked: d.slopeBlocked(angle)});
  for (const run of [-1, 0, .001, .25, 1, 2.5, 10]) traversalMath.push({run, snap: d.slopeSnapM(run)});
  const traversalQueries = [];
  const modes = ['bare', 'raised', 'structBoundary', 'deck', 'deckBoundary', 'tunnel', 'tunnelBoundary', 'transition'];
  for (const mode of modes) for (const grade of [-1, 0, .2, 1]) for (const direction of [[1, 0], [.25, -.5], [0, 0], [.00001, 0]])
    for (const flag of ['ground', 'flying', 'air', 'rising']) {
      const context = new Original();
      const queries = [];
      const height = (x, z) => 10 + grade * x + grade * .5 * z;
      const surface = (x, z) => mode === 'raised' ? height(x, z) + d.SLOPE.STRUCT_M + .0001
        : mode === 'structBoundary' ? height(x, z) + d.SLOPE.STRUCT_M
        : mode === 'deck' || mode === 'tunnel' || mode === 'tunnelBoundary' ? 20
        : mode === 'deckBoundary' ? 20 + rules.deckTolerance : mode === 'transition' && x > 0 ? 20 : height(x, z);
      const atDeck = mode === 'deck' || mode === 'deckBoundary' || mode === 'transition';
      context.pos = {x: 0, y: 20, z: 0}; context.vy = flag === 'rising' ? .001 : 0;
      context._env = {air: flag === 'air'}; context._flying = () => flag === 'flying';
      context._surf = (x, z, y) => {queries.push(['surface', x, z, y]); return surface(x, z);};
      context.terrain = {heightAt: (x, z) => {queries.push(['height', x, z]); return height(x, z);},
        tunnelAt: (x, z) => {queries.push(['tunnel', x, z]); return mode === 'tunnel' ? {ceil: 21} : mode === 'tunnelBoundary' ? {ceil: 20} : null;},
        deckY: (x, z, margin) => {queries.push(['deck', x, z, margin]); return atDeck ? 20 : null;}};
      const offset = direction.map(value => value * 2.5);
      const angle = context._slopeDegAlong(0, 0, 20, ...offset);
      const angleQueries = queries.splice(0);
      const factor = context._slopeMoveF({x: direction[0], z: direction[1]});
      traversalQueries.push({mode, grade, direction, flag, offset, angle, factor, angleQueries, speedQueries: queries.splice(0)});
    }
  const traversalSnap = [];
  for (const run of [0, .05, .25, 1]) for (const drop of [0, .01, .5, 2, 10]) for (const vertical of [-1, 0, .001])
    for (const low of [false, true]) for (const above of [0, .05, .050001]) {
      const context = {pos: {x: run, y: 10 + above, z: 0}, vy: vertical, _lowG: low, _surf: () => 10};
      traversalSnap.push({run, drop, vertical, low, above, result: snap.call(context, 0, 0, 10 + above, 10 - drop)});
    }
  const traversalSlides = [];
  for (const grade of [[1, 0], [0, 1], [1, 1], [1, -1], [-1, -1], [0, 0]]) for (const offset of [[1, 1], [1, 0], [0, 1], [-1, 1]]) {
    const context = {pos: {x: offset[0], y: 12, z: offset[1]}, vel: {x: 3, z: 4}};
    const passable = (x, z) => !d.slopeBlocked(d.slopeDeg(x * grade[0] + z * grade[1], Math.hypot(x, z)));
    const blocked = !passable(...offset);
    traversalSlides.push({grade, offset, blocked, result: slide.call(context, 0, 0, 10, passable)});
  }
  const traversalWarnings = [];
  for (const blocked of [false, true]) for (const offset of [[0, 0], [.000001, 0], [0, -.000001]]) {
    const notices = [], context = {pos: {x: offset[0], z: offset[1]}, _slopeWarnAt: rules.warningInitial, hud: {feed: text => notices.push(text)}};
    const steps = [];
    for (const now of [0, rules.warningInterval, rules.warningInterval + .000001, rules.warningInterval * 2, rules.warningInterval * 2 + .000002]) {
      warn.call(context, now, blocked, 0, 0);
      steps.push({now, last: context._slopeWarnAt, notices: notices.splice(0)});
    }
    traversalWarnings.push({blocked, offset, steps});
  }
  return {rules, fixtures: {traversalMath, traversalQueries, traversalSnap, traversalSlides, traversalWarnings}};
}
