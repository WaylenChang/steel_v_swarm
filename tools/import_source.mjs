import { readFile, writeFile, mkdir, cp } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { combatReferences } from './combat_references.mjs';
import { projectileReferences } from './projectile_references.mjs';
import { lineReferences } from './line_references.mjs';
import { targetingReferences } from './targeting_references.mjs';
import { missileReferences } from './missile_references.mjs';
import { structureReferences } from './structure_references.mjs';
import { reachabilityReferences } from './reachability_references.mjs';
import { modelReferences } from './model_references.mjs';
import { footprintReferences } from './footprint_references.mjs';
import { cameraReferences } from './camera_references.mjs';
import { burstReferences } from './burst_references.mjs';
import { statusReferences } from './status_references.mjs';
import { movementReferences } from './movement_references.mjs';
import { fieldReferences } from './field_references.mjs';
import { companionReferences } from './companion_references.mjs';
import { carrierReferences } from './carrier_references.mjs';
import { npcReferences } from './npc_references.mjs';
import { waveReferences } from './wave_references.mjs';
import { weatherReferences } from './weather_references.mjs';
import { environmentReferences } from './environment_references.mjs';
import { sceneryReferences } from './scenery_references.mjs';
import { sceneReferences } from './scene_references.mjs';
import { supplyReferences } from './supply_references.mjs';
import { thirdReferences } from './third_references.mjs';
import { matchReferences } from './match_references.mjs';

// Offline migration only: evaluate the source's settlement seams instead of copying derived numbers.
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const source = resolve(process.argv[2] || join(root, '..', 'steel_vs_swarm'));
const load = file => import(pathToFileURL(join(source, file)).href);
const d = await load('public/js/data.js');
const v = await load('public/js/venues.js');
const { BattleSim, cumLen, pointAt } = await load('server/sim.js');
const { mulberry32 } = await load('public/js/rng.js');
const buildings = await load('public/js/mapBuilding.js');
const narrative = await load('public/js/story.js');
const civilianContent = await load('public/js/civilianContent.js');
const gameSource = await readFile(join(source, 'public/js/game.js'), 'utf8');
const mainSource = await readFile(join(source, 'public/js/main.js'), 'utf8');
const feedBody = /feed: \(text\) => \{([\s\S]*?)\n    \},/.exec(mainSource.replace(/\r\n/g, '\n'))?.[1];
const feedLimit = /feedBox.children.length > (\d+)/.exec(feedBody || '');
const feedLifetime = /setTimeout\(\(\) => div.remove\(\), (\d+)\)/.exec(feedBody || '');
if (!feedLimit || !feedLifetime) throw new Error('Source HUD feed rules missing');
const sprintMatch = /const boost = ax\.boost \? ([\d.]+) : 1/.exec(gameSource);
if (!sprintMatch) throw new Error('Source sprint seam not found');
const arcPoints = /const ARC_MAXP = (\d+);/.exec(gameSource);
const arcColors = /const col = fc.close \? (0x[\da-f]+) : !fc.ok \? (0x[\da-f]+) : fc.aa \? (0x[\da-f]+) : fc.high \? (0x[\da-f]+) :/.exec(gameSource);
if (!arcPoints || !arcColors) throw new Error('Source arc preview seam not found');
const coneAngle = /const LIM = opt\?\.lim \?\? ([\d.]+)/.exec(gameSource);
const lockInterval = /now - \(this\._lockAt \|\| 0\) < ([\d.]+)/.exec(gameSource);
const obstructionTolerance = /dB < ro\.distanceTo\(c\) - ([\d.]+)/.exec(gameSource);
if (!coneAngle || !lockInterval || !obstructionTolerance) throw new Error('Source acquisition seams not found');
const serialize = value => JSON.parse(JSON.stringify(value, (_, item) =>
  item instanceof Set ? [...item] : item instanceof Map ? Object.fromEntries(item) : item));
const constants = {};
for (const [key, value] of Object.entries(d)) {
  if (typeof value !== 'function') constants[key] = serialize(value);
}
const heroes = {};
for (const [id, ch] of Object.entries(d.CHARACTERS)) {
  heroes[id] = {
    ...ch, armor: d.heroArmor(id), radius: d.hitR({ hero:true, kind:ch.kind, ch:id }),
    height: d.hitH({ hero:true, kind:ch.kind, ch:id }), speed: d.heroMobility(ch.kind, ch.mods),
    colliders: {ground:d.selfCollider(d.heroTargetH(ch.kind,id),false),air:d.selfCollider(d.heroTargetH(ch.kind,id),true)},
    flySpeed: d.heroMobility(ch.kind, ch.mods, true),
    weapons: {}, abilities: {},
  };
  for (const slot of ['light', 'heavy']) {
    heroes[id].weapons[slot] = Array.from({ length: d.ECON.UPGRADES[slot === 'light' ? 'lw' : 'hw'].max + 1 }, (_, i) => {
      const def = d.heroWeapon(id, slot, i + 1);
      return { ...def, area: d.aoeClass(def), trajectory: d.trajClass(def), reachRule: d.reachRule(def),
        burst: { count: d.fireBurstN(def), gap: d.fireBurstGap(def) },
        lanceRadius: d.lanceR(def), lancePen: d.lancePen(def),
        fanSubs: d.fanSubs(def), fanMaxBuildingHits: d.fanBuildingMaxHits(def),
        fanRangeFactors: Array.from({ length: d.fanSubs(def) }, (_, bin) => d.fanBinRangeF(def, bin)),
        projectile: { speed: d.shotV0(def), antiAirSpeed: d.shotV0(def, true), arm: d.armingOf(def), fuel: d.chaseCapS(def), flightCap: d.flightCapS(def),
          core: d.blastCoreR(def), launchDistance: d.guidedLaunchDist(def) },
        heavyMp: slot === 'heavy' ? d.heavyMpCost(def) : 0 };
    });
  }
  for (const slot of ['def', 'atk']) {
    heroes[id].abilities[slot] = Array.from({ length: d.ECON.UPGRADES[slot].max + 1 }, (_, i) => d.heroAbility(id, slot, i + 1));
  }
}
const maps = [];
for (const venue of v.VENUES.filter(item => !item.story)) {
  const available = v.venueAvailability(venue, 5);
  if (!available.available) continue;
  const variants = {};
  for (let size = d.TEAM.MIN; size <= d.TEAM.MAX; size++) {
    const cfg = v.venueConfig(venue, size);
    const sim = new BattleSim(cfg);
    const wavePrefill = [];
    sim._spawnLaneWave = (lane,side,wave,lead) => wavePrefill.push({lane,side,wave,lead});
    sim._prefillLanes();
    variants[size] = {
      config: cfg, bounds: d.battleRect(cfg),
      authority_bounds: {minX:sim.bounds.minX,maxX:sim.bounds.maxX,minZ:-sim.bounds.maxZ,maxZ:-sim.bounds.minZ},
      wave_prefill: wavePrefill,
      lane_turns:sim.lanes.map(lane=>d.laneTacticsXZ(lane).turns),
      bases: Object.fromEntries(Object.entries(cfg.bases).map(([side, ll]) => [side, d.llToXZ(...ll, cfg.center)])),
      lanes: cfg.lanes.map(lane => lane.map(ll => d.llToXZ(...ll, cfg.center))),
      hero_spawns: Object.fromEntries(['SWARM','STEEL'].map(side => [side,
        Array.from({length:size}, (_, slot) => {
          const [x,z] = sim._spawnPoint(side,slot);
          const [dx,dz] = sim._spawnAimDir(side,slot,x,z);
          return {position:[x,-z],direction:[dx,-dz]};
        })])),
      structures: [...sim.ents.values()].filter(e => ['base', 'tower'].includes(e.kind)).map(e =>
        ({ kind: e.kind, side: e.side, position: [e.x, e.y || 0, -e.z], lane: e.lane ?? 0, hp: e.hp })),
    };
  }
  maps.push({ id: venue.id, name: venue.name, variants });
}
const rng = mulberry32(123456789);
const unitVolumes=Object.fromEntries(Object.keys(d.UNITS).map(kind=>[kind,Object.fromEntries(['SWARM','STEEL','GUER','MILI'].map(side=>
  [side,{radius:d.hitR({kind,side}),height:d.hitH({kind,side})}]))]));
const missileReference = await missileReferences(d, BattleSim, maps[0].variants['1'].config, source, gameSource);
const structureReference = await structureReferences(d, BattleSim, maps[0].variants['1'].config, source, root, gameSource);
const reachabilityReference = await reachabilityReferences(d, gameSource, source);
const cameraReference = await cameraReferences(d, source, gameSource);
const modelReference = await modelReferences(source, gameSource, cameraReference.profiles);
const carrierReference = carrierReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32);
const npcReference = await npcReferences(d, BattleSim, maps[0].variants['1'].config, source);
const waveReference = waveReferences(d, BattleSim, maps[0].variants['1'].config, cumLen, pointAt, mulberry32);
const weatherReference = await weatherReferences(d, BattleSim, maps[0].variants['1'].config, source);
const glowOpacity = /opacity: warn \? ([\d.]+) : ([\d.]+)/.exec(gameSource);
const glowColor = /color: warn \? (0x[\da-f]+) : sideInfo\(this.side\).color/.exec(gameSource);
const glowSize = /sp.scale.setScalar\(Math.max\(([\d.]+), Math.max\(h, r \* 2\) \* ([\d.]+)\)\)/.exec(gameSource);
if (!glowOpacity || !glowColor || !glowSize) throw new Error('Source weapon glow style seams missing');
const fixtures = {
  ...carrierReference.fixtures,
  ...npcReference.fixtures,
  ...waveReference.fixtures,
  ...weatherReference.fixtures,
  ...await environmentReferences(d, BattleSim, maps[0].variants['1'].config, source, gameSource),
  ...sceneryReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32, weatherReference.rules.surface),
  ...sceneReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32),
  ...supplyReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32),
  ...await thirdReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32, source),
  ...matchReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32),
  ...companionReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32),
  ...await fieldReferences(d, BattleSim, maps[0].variants['1'].config, source),
  ...await movementReferences(d, source, gameSource),
  ...statusReferences(d, BattleSim, maps[0].variants['1'].config, mulberry32),
  ...burstReferences(d, gameSource),
  ...await footprintReferences(d, gameSource, source),
  ...modelReference.fixtures,
  ...cameraReference.fixtures,
  ...structureReference.fixtures,
  ...missileReference.fixtures,
  ...combatReferences(d, BattleSim, maps[0].variants['1'].config, buildings),
  ...await projectileReferences(d, gameSource, source),
  ...lineReferences(d, BattleSim, maps[0].variants['1'].config, cameraReference.profiles),
  ...await targetingReferences(d, gameSource, source, BattleSim, maps[0].variants['1'].config, cameraReference.profiles),
  reachability: reachabilityReference.reachability,
  volumes: [
    ...Object.entries(d.CHARACTERS).map(([id, ch]) => {
      const actor = {hero:true, kind:ch.kind, ch:id};
      return {kind:ch.kind, side:ch.side, character:id, radius:d.hitR(actor), height:d.hitH(actor),
        eye:cameraReference.profiles[id].ground.eye, forward:cameraReference.profiles[id].ground.forward,
        ground:d.selfCollider(d.heroTargetH(ch.kind,id),false), air:d.selfCollider(d.heroTargetH(ch.kind,id),true)};
    }),
    ...Object.keys(d.UNITS).flatMap(kind => ['SWARM','STEEL'].map(side =>
      ({kind,side,character:'',radius:d.hitR({kind,side}),height:d.hitH({kind,side})}))),
  ],
  rng: Array.from({ length: 32 }, () => rng()),
  shield: [0, 10, 100].flatMap(sp => [0, .3, 1].flatMap(spPierce => [0, .5, 1].map(vsSp => {
    const def = { spPierce, vsSp, vsHp: 1.25 };
    return { def, damage: 80, shield: sp, result: d.shieldSplit(def, 80, sp) };
  }))),
  envelope: [50, 100].flatMap(range => [-150, -50, 0, 25, 100].flatMap(y => [0, 30, 80, 120].map(x =>
    ({ range, delta: [x, y, 0], result: d.inWeaponRange(range, x, 0, y) })))),
  falloff: Object.values(heroes).flatMap(h => Object.values(h.weapons).flatMap(tiers => tiers.map(def =>
    ({ def, samples: [0, .35, .6, 1].map(f => ({ distance: def.range * f, result: d.dmgFalloff(def, def.range * f) })) })))),
  fan: Object.values(heroes).flatMap(h => Object.values(h.weapons).flatMap(tiers => tiers.filter(def => def.fan).flatMap(def =>
    [0, def.fanSubs >> 1, def.fanSubs - 1].flatMap(bin => [0, .3, .7].flatMap(phi => [0.6, 7, 20].map(radius =>
      ({ def, bin, distance: def.range, phi, radius, result: d.fanBinHitD(def, bin, def.range, phi, radius) }))))))),
  zones: [0, 1, 3, 6, 10].flatMap(x => [-5, 0, 5].flatMap(z => [.6, 7, 20].map(radius =>
    ({ offset: [x, z], radius, beam: 5.4, result: d.lanceZones(x, z, radius, 5.4) })))),
};
await mkdir(join(root, 'data'), { recursive: true });
for (const [name, value] of Object.entries({ balance: { constants, heroes, unitVolumes,
  structure: structureReference.rules,
  modelGeometry: modelReference.geometry,
  cockpit: modelReference.cockpits,
  cockpitRules: modelReference.cockpitRules,
  projectileVisual: modelReference.projectileVisual,
  companions: modelReference.companionProfiles,
  hazard_visuals: modelReference.hazardProfiles,
  loot_visuals: modelReference.lootProfiles,
  hud_feed: {maximum:Number(feedLimit[1]),lifetime:Number(feedLifetime[1])/1000},
  side_unknown: serialize(d.sideInfo(null)),
  civilian_appearance: {occupations:serialize(civilianContent.CIVILIAN_OCCUPATIONS),options:serialize(civilianContent.CIVILIAN_OPTIONS)},
  hazard_volumes: Object.fromEntries([...Object.keys(d.HAZARDS),'aasite','relay'].map(kind=>[kind,{radius:d.hitR({kind}),height:d.hitH({kind})}])),
  carrier: carrierReference.rules,
  npc: npcReference.rules,
  wave_rules: waveReference.rules,
  weather: weatherReference.rules,
  cameraProfiles: cameraReference.profiles, cameraRules: cameraReference.rules,
  footprintGlow: { warningOpacity: Number(glowOpacity[1]), opacity: Number(glowOpacity[2]),
    warningColor: Number(glowColor[1]), minimumSize: Number(glowSize[1]), sizeFactor: Number(glowSize[2]) },
  reachability: reachabilityReference.reachabilityRules,
  missile: missileReference.metadata,
  projectilePreview: { maxPoints: Number(arcPoints[1]), colors: Object.fromEntries(['close','blocked','aa','high'].map((key, i) => [key, Number(arcColors[i + 1])])) },
  targeting: { coneAngle: Number(coneAngle[1]), lockInterval: Number(lockInterval[1]), obstructionTolerance: Number(obstructionTolerance[1]) },
  movement: { sprint: Number(sprintMatch[1]) }, charge: Array.from({ length: 4 }, (_, i) => d.chargeF(i)),
  waves: Array.from({ length: 16 }, (_, i) => d.waveComp(i)) }, maps, fixtures,
  narrative: serialize(narrative), structures: structureReference.worlds })) {
  await writeFile(join(root, 'data', `${name}.json`), JSON.stringify(value));
}
for (const folder of ['models/reference', 'models/combat', 'models/factions', 'mech_avatars', 'story']) {
  await cp(join(source, 'public/assets', folder), join(root, 'assets', folder), { recursive: true });
}
await mkdir(join(root, 'assets/ui'), { recursive: true });
await writeFile(join(root, 'assets/ui/footprint-glow.png'), Buffer.from(modelReference.glowPng, 'base64'));
await mkdir(join(root, 'data/cockpits'), { recursive: true });
for (const [character, graph] of Object.entries(modelReference.cockpitGraphs))
  await writeFile(join(root, 'data/cockpits', `${character}.json`), JSON.stringify(graph));
await mkdir(join(root, 'data/projectiles'), { recursive: true });
for (const [key, graph] of Object.entries(modelReference.projectileGraphs))
  await writeFile(join(root, 'data/projectiles', `${key}.json`), JSON.stringify(graph));
await mkdir(join(root, 'data/companions'), { recursive: true });
for (const [key, graph] of Object.entries(modelReference.companionGraphs))
  await writeFile(join(root, 'data/companions', `${key}.json`), JSON.stringify(graph));
await mkdir(join(root, 'data/hazards'), { recursive: true });
for(const [key,graph] of Object.entries(modelReference.hazardGraphs))
  await writeFile(join(root, 'data/hazards', `${key}.json`), JSON.stringify(graph));
await mkdir(join(root, 'data/loot'), { recursive: true });
for(const [key,graph] of Object.entries(modelReference.lootGraphs))
  await writeFile(join(root, 'data/loot', `${key}.json`), JSON.stringify(graph));
await cp(join(source, 'public/audio'), join(root, 'assets/audio'), { recursive: true });
await cp(join(source, 'LICENSE'), join(root, 'LICENSE'));
const inputs = ['public/js/data.js', 'public/js/venues.js', 'public/js/venueLanes.js', 'public/js/rng.js', 'public/js/game.js', 'public/js/main.js', 'public/js/biomes.js', 'public/js/vfx.js', 'public/js/toon.js', 'public/js/mapBuilding.js', 'server/sim.js', 'out/forest_review/three.module.js'];
const hashes = {};
for (const file of new Set([...inputs, ...modelReference.inputs])) hashes[file] = createHash('sha256').update(await readFile(join(source, file))).digest('hex');
await writeFile(join(root, 'data/provenance.json'), JSON.stringify({ inputs: hashes, heroes: Object.keys(heroes).length,
  qualifiedMaps: maps.length, runtime: 'GDScript', sourceLicense: 'Apache-2.0' }, null, 2));
console.log(`Imported ${Object.keys(heroes).length} heroes, ${maps.length} qualified maps and native glTF assets.`);
