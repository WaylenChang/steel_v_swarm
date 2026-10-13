import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

export async function structureReferences(d, BattleSim, config, source, root, gameSource) {
  const main = await readFile(join(source, 'public/js/main.js'), 'utf8');
  const simSource = (await readFile(join(source, 'server/sim.js'), 'utf8')).replace(/\r\n/g, '\n');
  const biome = (await readFile(join(source, 'public/js/biomes.js'), 'utf8')).replace(/\r\n/g, '\n');
  const extract = name => {
    const start = biome.indexOf(`export function ${name}(`), end = biome.indexOf('\n}', start);
    if (start < 0 || end < 0) throw new Error(`Missing source structure query: ${name}`);
    return biome.slice(start + 7, end + 2);
  };
  const deckCode = extract('makeDeckIndex'), tunnelCode = extract('makeTunnelIndex');
  const deckIndex = new Function(`return ${deckCode}`)();
  // Roof output is outside this classifier; source floor/ceiling/open selection executes unchanged.
  const tunnelIndex = new Function('tunRoofTop', `return ${tunnelCode}`)(cy => cy);
  const grab = (text, regex) => {
    const match = regex.exec(text);
    if (!match) throw new Error(`Missing structure seam: ${regex}`);
    return Number(match[1]);
  };
  const rules = {
    deckCell: grab(deckCode, /const CELL = ([\d.]+)/), tunnelCell: grab(tunnelCode, /const CELL = ([\d.]+)/),
    deckPad: grab(deckCode, /const pad = d\.hw \+ ([\d.]+)/), tunnelPad: grab(tunnelCode, /const pad = d\.hw \+ ([\d.]+)/),
    deckLongTolerance: grab(deckCode, /const LONG_TOL = ([\d.]+)/),
    tunnelLongTolerance: grab(tunnelCode, /Math\.sqrt\(len2\) > ([\d.]+)/),
    deckMargin: grab(gameSource, /deckY\?\.\(this\.pos\.x, this\.pos\.z, ([\d.]+)\)/),
    bridgeThreshold: grab(gameSource, /!inTun && sy > th \+ ([\d.]+)/),
    bridgeHeightTolerance: grab(gameSource, /Math\.abs\(sy - dY2\) < ([\d.]+)/),
  };
  const uploadStart = main.indexOf('      const slabs = ['), uploadEnd = main.indexOf(';', uploadStart);
  if (uploadStart < 0 || uploadEnd < 0) throw new Error('Missing source slab upload');
  const upload = new Function('ud', 'rd', 'LOS', `${main.slice(main.lastIndexOf('      const decks = ud.decks', uploadStart), uploadEnd + 1)} return slabs;`);
  const rd = value => Math.round(value * 10) / 10;
  const poseStart = gameSource.indexOf('      const sy = this._surf(this.pos.x, this.pos.z, this.pos.y);');
  const poseEnd = gameSource.indexOf('      const lev = inTun ? 2 : onBridge ? 1 : 0;', poseStart);
  if (poseStart < 0 || poseEnd < 0) throw new Error('Missing source player structure pose');
  const playerPose = new Function(`return function() { ${gameSource.slice(poseStart, poseEnd)}
    const lev = inTun ? 2 : onBridge ? 1 : 0; return {level:lev,reference:sEff}; }`)();
  const accepted = raw => {
    const sim = new BattleSim(config);
    const entries = [], seen = new Set();
    class OrderedMap extends Map {
      set(key, value) {
        value.push = (...items) => {
          for (const item of items) if (!seen.has(item)) { seen.add(item); entries.push(item); }
          return Array.prototype.push.apply(value, items);
        };
        return super.set(key, value);
      }
    }
    const name = '_ingestSlabs', start = simSource.indexOf(`\n  ${name}(`), end = simSource.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error('Missing source slab ingestion');
    const method = simSource.slice(start + 1, end + 4).trimStart();
    const ingest = new Function('LOS', 'Map', `return function ${method.slice(name.length)}`)(d.LOS, OrderedMap);
    ingest.call(sim, { slabs: raw });
    return { sim, entries };
  };
  const nativePoint = (x, z) => [Math.fround(x), Math.fround(-z)];
  const structureSeparation = [], structureLevels = [], structureClient = [], structureWorlds = [], structureBlasts = [];
  const groups = [];
  for (const angle of [0, .7, Math.PI / 2]) for (const gal of [0, 1, 2, 3]) {
    const nx = Math.cos(angle), nz = Math.sin(angle), cx = -65, cz = 130;
    const slab = [cx - nx * 40, cz - nz * 40, cx + nx * 40, cz + nz * 40, 8, 2, gal];
    const at = (along, lateral) => nativePoint(cx + nx * along - nz * lateral, cz + nz * along + nx * lateral);
    groups.push({ name: `tunnel angle=${angle} gal=${gal}`, raw: [slab], inner: at(0, 0),
      points: [[0, 0], [0, 12], [0, -12], [60, 0], [-60, 0], [60, 12], [60, 40], [0, 8], [0, 8.01]].map(p => at(...p)) });
  }
  groups.push({ name: 'bridge capsule caps', raw: [[-40, 0, 40, 0, 8, 1]], inner: [0, 0], points: [[0, 0], [0, 8], [0, 8.01], [45, 0], [48, 0], [48.01, 0], [-45, 0]] });
  groups.push({ name: 'overlapping bridge before tunnel', raw: [[-40, 0, 40, 0, 8, 1], [-40, 0, 40, 0, 8, 2, 3]], inner: [0, 0], points: [[0, 0], [0, 12], [60, 0]] });
  groups.push({ name: 'overlapping closed gallery veto', raw: [[-40, 0, 40, 0, 8, 2, 3], [-40, 0, 40, 0, 8, 2, 0]], inner: [0, 0], points: [[0, 0], [0, 12], [0, -12]] });
  groups.push({ name: 'degenerate tunnel', raw: [[0, 0, 0, 0, 8, 2, 3]], inner: [0, 0], points: [[0, 0], [0, 10]] });
  groups.push({ name: 'no uploaded slabs', raw: [], inner: [0, 0], points: [[0, 0], [0, 12]] });
  for (const group of groups) {
    const { sim, entries } = accepted(group.raw);
    for (const point of group.points) for (const level of [null, 0, 1, 2]) for (const targetLevel of [0, 1, 2]) {
      const target = { kind: 'robot', hero: true, lev: targetLevel, x: point[0], z: -point[1] };
      const result = sim._slabSep(level, group.inner[0], -group.inner[1], target);
      structureSeparation.push({ name: group.name, slabs: entries, level: level ?? -1, impact: group.inner, target: point, target_level: targetLevel, result });
    }
    const specs = [{ kind: 'tower', hero: true, lev: 2 }, { kind: 'base', hero: false },
      { kind: 'robot', hero: true, lev: 0 }, { kind: 'robot', hero: true, lev: 1 },
      { kind: 'robot', hero: true }, { kind: 'soldier', lane: 0 }, { kind: 'soldier' },
      { kind: 'drone', hero: true, y: d.LOS.TUN_CLEAR_M - .01 },
      { kind: 'drone', hero: true, y: d.LOS.TUN_CLEAR_M }, { kind: 'heli', y: 20 }];
    for (const point of group.points) for (const spec of specs) {
      structureLevels.push({ slabs: entries, point, spec: { kind: spec.kind, hero: !!spec.hero,
        level: spec.lev ?? null, altitude: spec.y || 0, has_lane: spec.lane != null },
        result: sim._unitLev({ ...spec, x: point[0], z: -point[1] }) });
    }
  }
  for (const group of groups) {
    const { sim, entries } = accepted(group.raw);
    for (const level of [null, 0, 1, 2]) for (const friendly of [false, true]) {
      const targets = group.points.slice(0, 5).map((point, i) => ({ id: i + 1, kind: 'soldier', lane: 0,
        x: point[0], z: -point[1], side: i % 2 ? 'STEEL' : 'SWARM', hp: 1000 }));
      sim.ents = new Map(targets.map(t => [t.id, t]));
      sim._dodgeP = () => 0; sim._missP = () => 0; sim._applyHitElem = () => {};
      const hits = [];
      sim._damage = (t, amount) => hits.push({ id: t.id, amount });
      sim._blast({ side: 'STEEL', kind: 'base' }, { r: 30, pen: 0 }, group.inner[0], -group.inner[1], 1, level, friendly, 20);
      structureBlasts.push({ name: group.name, slabs: entries, level: level ?? -1, impact: [...group.inner], friendly,
        targets: targets.map(t => ({ id: t.id, side: t.side, point: [t.x, -t.z] })), hits });
    }
  }
  const geometryGroups = [
    { name: 'bridge and rooftop', decks: [{ x1: -40, z1: 0, y1: 10, x2: 40, z2: 0, y2: 20, hw: 8 }], tunnels: [] },
    { name: 'covered tunnel and open approach', decks: [], tunnels: [
      { x1: -40, z1: 0, fy1: 0, cy1: 8, x2: 40, z2: 0, fy2: 4, cy2: 12, hw: 8 },
      { x1: 40, z1: 0, fy1: 4, cy1: 12, x2: 60, z2: 0, fy2: 8, cy2: 16, hw: 8, open: true }] },
    { name: 'lowest open tunnel wins', decks: [], tunnels: [
      { x1: -40, z1: 0, fy1: -5, cy1: 3, x2: 40, z2: 0, fy2: -5, cy2: 3, hw: 8, open: true },
      { x1: -40, z1: 0, fy1: 0, cy1: 8, x2: 40, z2: 0, fy2: 0, cy2: 8, hw: 8 }] },
  ];
  const clientCase = (name, geometry, point, surface, ground) => {
    const deckAt = deckIndex(geometry.decks), tunnelAt = tunnelIndex(geometry.tunnels);
    const ctx = { pos: { x: point[0], y: point[1], z: point[2] }, _surf: () => surface,
      terrain: { heightAt: () => ground, tunnelAt, deckY: deckAt } };
    const tunnel = tunnelAt(point[0], point[2]);
    structureClient.push({ name, ...geometry, point, surface, ground, result: playerPose.call(ctx),
      deck: deckAt(point[0], point[2], rules.deckMargin), tunnel: tunnel ? { floor: tunnel.floor, ceil: tunnel.ceil, open: tunnel.open } : {} });
  };
  for (const group of geometryGroups) for (const x of [0, 40, 40.74, 41.01, 55]) for (const z of [0, 8, 8.01, 11.01]) {
    for (const y of [1, 8, 8.01, 15, 40]) for (const surface of [0, 15, 15.59, 15.61, 30])
      clientCase(group.name, group, [x, y, z].map(Math.fround), surface, 0);
  }
  const worlds = {};
  for (const file of (await readdir(join(root, 'data/worlds'))).filter(f => f.endsWith('.json')).sort()) {
    const world = JSON.parse(await readFile(join(root, 'data/worlds', file), 'utf8'));
    const raw = upload(world, rd, d.LOS), { sim, entries } = accepted(raw);
    const key = file.slice(0, -5);
    worlds[key] = entries;
    const probes = [];
    for (const s of entries) {
      const point = nativePoint((s[0] + s[2]) / 2, (s[1] + s[3]) / 2);
      const target = { kind: 'robot', hero: true, lev: 0, x: point[0], z: -point[1] };
      probes.push({ point, level: sim._slabLevAt(target.x, target.z), separation: sim._slabSep(2, target.x, target.z, target) });
    }
    structureWorlds.push({ key, count: entries.length, probes });
  }
  return { rules, worlds, fixtures: { structureSeparation, structureLevels, structureClient, structureWorlds, structureBlasts } };
}
