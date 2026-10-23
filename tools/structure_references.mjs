import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { captureSupportBundle } from './support_capture.mjs';
import {readWorldHeader} from './world_source.mjs';

export function sourceSlabUpload(main) {
  const start = main.indexOf('      const slabs = ['), end = main.indexOf(';', start);
  const decks = main.lastIndexOf('      const decks = ud.decks', start);
  if (start < 0 || end < 0 || decks < 0) throw new Error('Missing source slab upload');
  return new Function('ud', 'rd', 'LOS', `${main.slice(decks, end + 1)} return slabs;`);
}

export function acceptedSourceSlabs(d, BattleSim, config, simSource, raw) {
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
}

export async function structureReferences(d, BattleSim, config, source, root, gameSource) {
  const main = (await readFile(join(source, 'public/js/main.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const simSource = (await readFile(join(source, 'server/sim.js'), 'utf8')).replace(/\r\n/g, '\n');
  const biome = (await readFile(join(source, 'public/js/biomes.js'), 'utf8')).replace(/\r\n/g, '\n');
  const extract = name => {
    const start = biome.indexOf(`export function ${name}(`), end = biome.indexOf('\n}', start);
    if (start < 0 || end < 0) throw new Error(`Missing source structure query: ${name}`);
    return biome.slice(start + 7, end + 2);
  };
  const deckCode = extract('makeDeckIndex'), tunnelCode = extract('makeTunnelIndex');
  const deckIndex = new Function(`return ${deckCode}`)();
  const blockerTopCode = extract('makeBlockerTopIndex');
  const blockerTopIndex = new Function(`return ${blockerTopCode}`)();
  const roofStart = main.indexOf('function makeRoofPlatformIndex('), roofEnd = main.indexOf('\n}', roofStart);
  if (roofStart < 0 || roofEnd < 0) throw new Error('Missing source polygon roof index');
  const roofCode = main.slice(roofStart, roofEnd + 2);
  const roofPlatformIndex = new Function(`return ${roofCode}`)();
  // Roof output is outside this classifier; source floor/ceiling/open selection executes unchanged.
  const tunnelIndex = new Function('tunRoofTop', `return ${tunnelCode}`)(cy => cy);
  const grab = (text, regex) => {
    const match = regex.exec(text);
    if (!match) throw new Error(`Missing structure seam: ${regex}`);
    return Number(match[1]);
  };
  const rules = {
    deckStep: grab(main, /const DECK_STEP = ([\d.]+)/),
    deckUnder: grab(main, /const DECK_UNDER = ([\d.]+)/),
    maximumMechHeight: grab(main, /const MAX_MECH_H = ([\d.]+)/),
    tunnelRoofThickness: grab(biome, /ROOF_T: ([\d.]+)/),
    deckCell: grab(deckCode, /const CELL = ([\d.]+)/), tunnelCell: grab(tunnelCode, /const CELL = ([\d.]+)/),
    deckPad: grab(deckCode, /const pad = d\.hw \+ ([\d.]+)/), tunnelPad: grab(tunnelCode, /const pad = d\.hw \+ ([\d.]+)/),
    deckLongTolerance: grab(deckCode, /const LONG_TOL = ([\d.]+)/),
    tunnelLongTolerance: grab(tunnelCode, /Math\.sqrt\(len2\) > ([\d.]+)/),
    deckMargin: grab(gameSource, /deckY\?\.\(this\.pos\.x, this\.pos\.z, ([\d.]+)\)/),
    bridgeThreshold: grab(gameSource, /!inTun && sy > th \+ ([\d.]+)/),
    bridgeHeightTolerance: grab(gameSource, /Math\.abs\(sy - dY2\) < ([\d.]+)/),
    blockerTopCell: grab(blockerTopCode, /const CELL = ([\d.]+)/),
    blockerTopPad: grab(blockerTopCode, /b\.x - r - ([\d.]+)/),
    blockerTopMargin: grab(main, /const BLK_MARGIN = ([\d.]+)/),
    roofCell: grab(roofCode, /cell = ([\d.]+)/),
    instanceClearanceFactor: grab(biome, /Math\.hypot\(S\.x, S\.z\) \/ 2 \* ([\d.]+)/),
    structurePadTolerance: grab(main, /Math\.abs\(p\.x - x\) < ([\d.]+) && Math\.abs\(p\.z - z\)/),
  };
  const structurePads = [];
  for (const kind of ['tower','base']) {
    const assignment = main.indexOf('terrain.' + kind + 'PadY =');
    const start = main.indexOf('(x, z) => {',assignment), end = main.indexOf('\n    };',start);
    if (assignment < 0 || start < 0 || end < 0) throw new Error('Missing original structure platform query: ' + kind);
    const code = main.slice(start,end+6);
    if (grab(code,/Math\.abs\(p\.x - x\) < ([\d.]+)/) !== rules.structurePadTolerance)
      throw new Error('Original platform query tolerances diverged');
    const factory = new Function(kind+'Pads','return '+code+';');
    for (const pads of [[],[{x:0,z:0,y:0}],[{x:0,z:0,y:14},{x:1,z:1,y:20},{x:-32,z:16,y:-5}]]) {
      const query = factory(pads);
      for (const x of [-32,-2.00001,-2,-1.99999,0,1,1.99999,2,3]) for (const z of [-2,-1.99999,0,1,2,16])
        structurePads.push({kind,pads:{[kind]:pads},x,z,result:query(x,z)});
    }
  }
  const upload = sourceSlabUpload(main);
  const rd = value => Math.round(value * 10) / 10;
  const poseStart = gameSource.indexOf('      const sy = this._surf(this.pos.x, this.pos.z, this.pos.y);');
  const poseEnd = gameSource.indexOf('      const lev = inTun ? 2 : onBridge ? 1 : 0;', poseStart);
  if (poseStart < 0 || poseEnd < 0) throw new Error('Missing source player structure pose');
  const playerPose = new Function(`return function() { ${gameSource.slice(poseStart, poseEnd)}
    const lev = inTun ? 2 : onBridge ? 1 : 0; return {level:lev,reference:sEff}; }`)();
  const accepted = raw => acceptedSourceSlabs(d, BattleSim, config, simSource, raw);
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
  const surfaceStart = main.indexOf('    terrain.surfaceAt = (x, z, curY) => {');
  const surfaceEnd = main.indexOf('\n    };', surfaceStart);
  if (surfaceStart < 0 || surfaceEnd < 0) throw new Error('Missing source projectile surfaceAt');
  const surfaceBody = main.slice(main.indexOf('{', surfaceStart) + 1, surfaceEnd);
  const surfaceAt = new Function('terrain', 'tunnelAt', 'deckY', 'DECK_MARGIN', 'DECK_STEP', 'DECK_UNDER', 'MAX_MECH_H',
    'blockerTop', 'BLK_MARGIN', 'roofPlatformAt', 'isWeatherFrozen', `return (x,z,curY) => {${surfaceBody}}`);
  const projectileSurfaces = [], flightSupportSurfaces = [];
  const supportGroups = [
    {name:'rotated building and giant rock tops', blockers:[
      {x:-32,z:16,y:2,h:18,hw2:8,hd2:3,ry:.7,bld:1,r:9},
      {x:0,z:0,y:1,h:8,r:6,std:1}, {x:0,z:0,y:0,h:50,r:4},
      {x:0,z:0,y:3,h:15,r:3,bld:1}], roofs:[]},
    {name:'courtyard with inactive upper roof', blockers:[], roofs:[
      {platform:1,y:20,outer:[[-10,-10],[10,-10],[10,10],[-10,10]], holes:[[[-2,-2],[2,-2],[2,2],[-2,2]]],
        bounds:{minX:-10,maxX:10,minZ:-10,maxZ:10}},
      {platform:1,active:false,y:40,outer:[[-10,-10],[10,-10],[10,10],[-10,10]], holes:[],
        bounds:{minX:-10,maxX:10,minZ:-10,maxZ:10}},
      {platform:1,y:8,outer:[[-3,-3],[3,-3],[0,3]],holes:[],bounds:{minX:-3,maxX:3,minZ:-3,maxZ:3}}]},
    {name:'empty source support set',blockers:[],roofs:[]}];
  supportGroups.push({name:'closed courtyard rings',blockers:[],roofs:[{
    platform:1,y:12,outer:[[-12,-8],[12,-8],[12,8],[-12,8],[-12,-8]],
    holes:[[[-4,-3],[4,-3],[4,3],[-4,3],[-4,-3]]],bounds:{minX:-12,maxX:12,minZ:-8,maxZ:8}}]});
  const supportQueries = [];
  for (const group of supportGroups) {
    const tops = blockerTopIndex(group.blockers), roofs = roofPlatformIndex(group.roofs);
    for (const x of [-40,-32,-24,-10,-6.6,-6,-3,-2,0,2,3,6,6.6,10,16])
      for (const z of [-10,-3,-2,0,2,3,10,16,20]) for (const margin of [0,rules.blockerTopMargin,1]) {
        const point = [x,z].map(Math.fround);
        supportQueries.push({...group,point,margin,top:tops(...point,margin),roof:roofs(...point)});
      }
  }
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const supportCaptures = [];
  for (const group of supportGroups) {
    const root = new THREE.Group();
    Object.assign(root.userData, {blockers:group.blockers,roofPlatforms:group.roofs,mapBuildings:new Map()});
    const captured = captureSupportBundle(root, THREE);
    const query = roofPlatformIndex(group.roofs);
    const probes = [];
    for (const x of [-20.125,-10.125,-5.125,-1.125,.125,3.125,8.125,12.125])
      for (const z of [-10.125,-5.125,-1.125,.125,3.125,7.125,10.125]) probes.push({point:[x,z],result:query(x,z)});
    supportCaptures.push({name:group.name,captured,probes});
  }
  const {buildingNear, buildingBounds} = await import(pathToFileURL(join(source, 'public/js/mapBuilding.js')).href);
  const clearAssignment = biome.indexOf('group.userData.clearAround =');
  const clearStart = biome.indexOf('(wx, wz, r) => {', clearAssignment), clearEnd = biome.indexOf('\n  };', clearStart);
  if (clearAssignment < 0 || clearStart < 0 || clearEnd < 0) throw new Error('Missing original scenery clearance closure');
  const clearScenery = new Function('group','buildingNear','detachMapBuilding','THREE','bldMeshes','landmarkG','climbs',
    'return ' + biome.slice(clearStart,clearEnd+4) + ';');
  const sceneryClearance = [];
  const radius = d.THIRD.BLD_CLEAR_R;
  const frame = (x,z,sx,sy,sz,angle=0)=>new THREE.Matrix4().compose(new THREE.Vector3(x,0,z),
    new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0,1,0),angle),new THREE.Vector3(sx,sy,sz));
  const sourceMatrices = [frame(0,0,12,20,8),frame(radius+9,0,12,20,8),frame(-radius-20,0,12,20,8),
    frame(0,-40,7,10,3,.7),frame(0,0,0,0,0),frame(8,0,-12,20,8,.7)];
  for (const camps of [[],[{x:0,z:0}],[{x:0,z:40}],[{x:1000,z:1000}],[{x:0,z:0},{x:0,z:40}]]) {
    const group = new THREE.Group();
    Object.assign(group.userData,{mapBuildings:new Map(),blockers:[]});
    const batch = new THREE.InstancedMesh(new THREE.BoxGeometry(1,1,1),new THREE.MeshBasicMaterial(),sourceMatrices.length);
    sourceMatrices.forEach((matrix,i)=>batch.setMatrixAt(i,matrix));
    const matrices = sourceMatrices.map((_,i)=>{const m=new THREE.Matrix4();batch.getMatrixAt(i,m);return m.toArray();});
    const landmarkSpecs = [{x:0,z:0,r:9},{x:radius+12,z:0,r:12},{x:0,z:0,r:9,key:'owned'}];
    const landmarks = landmarkSpecs.map(spec=>{const g=new THREE.Group();if(spec.key)g.userData.buildingKey=spec.key;return {...spec,g};});
    const clear = clearScenery(group,buildingNear,()=>{throw new Error('Unexpected owned building fixture');},THREE,[batch],landmarks,[]);
    for (const camp of camps) clear(camp.x,-camp.z,radius);
    sceneryClearance.push({camps,matrices,landmarks:landmarkSpecs,
      result:{matrices:sourceMatrices.map((_,i)=>{const m=new THREE.Matrix4();batch.getMatrixAt(i,m);return m.toArray();}),
        visible:landmarks.map(landmark=>landmark.g.visible)}});
    batch.geometry.dispose();batch.material.dispose();
  }
  const supportClearance = [];
  const records = [
    {key:'rotated',bounds:buildingBounds([{x:-17,z:22,y:0,h:20,hw2:8,hd2:3,ry:.7}])},
    {key:'separated-volumes',bounds:buildingBounds([{x:50,z:0,y:3,h:20,hw2:4,hd2:5,ry:0},
      {x:70,z:0,y:0,h:8,hw2:5,hd2:5,ry:0}])}];
  for (const camps of [[],[{x:-17,z:-22}],[{x:60,z:0}],[{x:1000,z:1000}],
    [{x:-17,z:-22},{x:60,z:0}]]) {
    const buildings = Object.fromEntries(records.filter(record=>camps.some(camp=>buildingNear(record.bounds,camp.x,-camp.z,d.THIRD.BLD_CLEAR_R)))
      .map(record=>[record.key,true]));
    supportClearance.push({records,camps,buildings});
  }
  const surfaceGroups = [...geometryGroups,
    {name:'stacked reachable decks',decks:[{x1:-40,z1:0,y1:5,x2:40,z2:0,y2:5,hw:8},
      {x1:-40,z1:0,y1:20,x2:40,z2:0,y2:20,hw:8}],tunnels:[]},
    {name:'terrain without structures',decks:[],tunnels:[]},
    ...supportGroups.map(group=>({...group,decks:[],tunnels:[]}))];
  for (const group of surfaceGroups) for (const ground of [0, 50]) {
    const roofIndex = new Function('tunRoofTop', `return ${tunnelCode}`)(cy => cy + rules.tunnelRoofThickness);
    const tunnelAt = roofIndex(group.tunnels), deckAt = deckIndex(group.decks);
    const query = surfaceAt({heightAt:()=>ground},tunnelAt,deckAt,rules.deckMargin,rules.deckStep,rules.deckUnder,rules.maximumMechHeight,
      blockerTopIndex(group.blockers || []),rules.blockerTopMargin,roofPlatformIndex(group.roofs || []),()=>false);
    const xs = group.blockers ? [-40,-32,-24,-10,-2,0,2,6,10] : [0,40,40.74,41.01,55];
    const zs = group.blockers ? [-10,-2,0,2,8,10,16,20] : [0,8,8.01,11.01];
    for (const x of xs) for (const z of zs) for (const y of [-.5,1,2.8,5,8,8.01,15,17.2,20,40,51]) {
      const point=[x,y,z].map(Math.fround);
      projectileSurfaces.push({name:group.name,...group,point,ground,result:query(point[0],point[2],point[1])});
      if (y === -.5) flightSupportSurfaces.push({name:group.name,...group,point:[point[0],point[2]],ground,result:query(point[0],point[2],Infinity)});
    }
  }
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
    console.log('SOURCE_STRUCTURE_WORLD '+file);
    const world = await readWorldHeader(join(root, 'data/worlds', file));
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
  return { rules, worlds, fixtures: { structureSeparation, structureLevels, structureClient, structureWorlds, structureBlasts,
    projectileSurfaces, flightSupportSurfaces, supportQueries, supportCaptures, supportClearance, sceneryClearance, structurePads } };
}
