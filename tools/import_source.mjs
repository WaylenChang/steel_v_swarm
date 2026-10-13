import { readFile, writeFile, mkdir, cp } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

// Offline migration only: evaluate the source's settlement seams instead of copying derived numbers.
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const source = resolve(process.argv[2] || join(root, '..', 'steel_vs_swarm'));
const load = file => import(pathToFileURL(join(source, file)).href);
const d = await load('public/js/data.js');
const v = await load('public/js/venues.js');
const { BattleSim } = await load('server/sim.js');
const { mulberry32 } = await load('public/js/rng.js');
const narrative = await load('public/js/story.js');
const gameSource = await readFile(join(source, 'public/js/game.js'), 'utf8');
const sprintMatch = /const boost = ax\.boost \? ([\d.]+) : 1/.exec(gameSource);
if (!sprintMatch) throw new Error('Source sprint seam not found');
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
      return { ...def, area: d.aoeClass(def), trajectory: d.trajClass(def),
        lanceRadius: d.lanceR(def), lancePen: d.lancePen(def),
        fanSubs: d.fanSubs(def), fanMaxBuildingHits: d.fanBuildingMaxHits(def),
        fanRangeFactors: Array.from({ length: d.fanSubs(def) }, (_, bin) => d.fanBinRangeF(def, bin)),
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
    variants[size] = {
      config: cfg, bounds: d.battleRect(cfg),
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
const unitVolumes=Object.fromEntries(Object.keys(d.UNITS).map(kind=>[kind,Object.fromEntries(['SWARM','STEEL'].map(side=>
  [side,{radius:d.hitR({kind,side}),height:d.hitH({kind,side})}]))]));
const fixtures = {
  volumes: [
    ...Object.entries(d.CHARACTERS).map(([id, ch]) => {
      const actor = {hero:true, kind:ch.kind, ch:id};
      return {kind:ch.kind, side:ch.side, character:id, radius:d.hitR(actor), height:d.hitH(actor),
        eye:d.hitH(actor)*d.SELF_F.eye,
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
for (const [name, value] of Object.entries({ balance: { constants, heroes, unitVolumes, movement: { sprint: Number(sprintMatch[1]) }, charge: Array.from({ length: 4 }, (_, i) => d.chargeF(i)),
  waves: Array.from({ length: 16 }, (_, i) => d.waveComp(i)) }, maps, fixtures,
  narrative: serialize(narrative) })) {
  await writeFile(join(root, 'data', `${name}.json`), JSON.stringify(value));
}
for (const folder of ['models/reference', 'models/combat', 'models/factions', 'mech_avatars', 'story']) {
  await cp(join(source, 'public/assets', folder), join(root, 'assets', folder), { recursive: true });
}
await cp(join(source, 'public/audio'), join(root, 'assets/audio'), { recursive: true });
await cp(join(source, 'LICENSE'), join(root, 'LICENSE'));
const inputs = ['public/js/data.js', 'public/js/venues.js', 'public/js/venueLanes.js', 'public/js/rng.js', 'public/js/game.js'];
const hashes = {};
for (const file of inputs) hashes[file] = createHash('sha256').update(await readFile(join(source, file))).digest('hex');
await writeFile(join(root, 'data/provenance.json'), JSON.stringify({ inputs: hashes, heroes: Object.keys(heroes).length,
  qualifiedMaps: maps.length, runtime: 'GDScript', sourceLicense: 'Apache-2.0' }, null, 2));
console.log(`Imported ${Object.keys(heroes).length} heroes, ${maps.length} qualified maps and native glTF assets.`);
