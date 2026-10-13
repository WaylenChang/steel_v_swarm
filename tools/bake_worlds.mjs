import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { join, resolve, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';
import { createHash } from 'node:crypto';

// Source execution is confined to migration; saved meshes and collision metadata run natively.
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const source = resolve(process.env.SVS_SOURCE || join(root, '..', 'steel_vs_swarm'));
const sha256 = value => createHash('sha256').update(value).digest('hex');
const sourceInputs = {};
for (const name of (await readdir(join(source, 'public/js'))).filter(name => name.endsWith('.js')).sort()) {
  sourceInputs[`public/js/${name}`] = sha256(await readFile(join(source, 'public/js', name)));
}
for (const name of ['tools/elevation_fixture.mjs', 'tools/osm_fixture.mjs', 'tools/venue_field.mjs', 'out/forest_review/three.module.js']) {
  sourceInputs[name] = sha256(await readFile(join(source, name)));
}
const generatorSha256 = sha256(await readFile(fileURLToPath(import.meta.url)));
const load = file => import(pathToFileURL(join(source, file)).href);
const d = await load('public/js/data.js');
const { readSrc, grabFn, grabBlock } = await load('tools/audit_src.mjs');
const { loadElevationFixture, validateElevationFixture, readOsmCapture } = await load('tools/osm_fixture.mjs');
const { osmRoadsFromElements, parseOsmFeatureElements } = await load('public/js/osmQuery.js');
const { serve, chromiumOrNull } = await load('tools/pw.mjs');
const {captureElevationFixture}=await load('tools/elevation_fixture.mjs');
const elevationSource = readSrc('tools', 'elevation_fixture.mjs');
const decode = new Function('inflateSync', `${grabFn(elevationSource, 'decodePng')}\nreturn decodePng;`)(inflateSync);
const mosaicOf = new Function(`${grabFn(elevationSource, 'makeMosaic')}\nreturn makeMosaic;`)();
const projection = elevationSource.slice(elevationSource.indexOf('const d2r ='), elevationSource.indexOf('const sha256 ='));
const sampler = new Function(`${projection}\n${grabFn(elevationSource, 'sampleMosaic')}\nreturn sampleMosaic;`)();
const biomesSource = readSrc('public', 'js', 'biomes.js');
const terrainSource=readSrc('public','js','terrain.js');
const imagerySeam = 'async function fetchImagery(bbox, onProgress) {';
if (!terrainSource.includes(imagerySeam)) throw new Error('Source imagery fallback seam missing');
// No imagery is captured offline; invoke the source's actual missing-service fallback.
const offlineTerrainSource = terrainSource.replace(imagerySeam,
  `${imagerySeam}\nthrow new Error('Offline geometry bake omits imagery');`);
const {TUN}=await load('tools/venue_field.mjs');
const deckIndexOf=new Function(`${grabFn(biomesSource,'makeDeckIndex')}\nreturn makeDeckIndex;`)();
const roofSource=biomesSource.split('\n').find(line=>line.startsWith('const tunRoofTop ='));
if(!roofSource) throw new Error('Source roof seam missing');
const tunnelIndexOf=new Function('TUN',`${roofSource}\n${grabFn(biomesSource,'makeTunnelIndex')}\nreturn makeTunnelIndex;`)(TUN);
const fieldSample=new Function('field','x','z','N','minX','maxX','minZ','maxZ',grabBlock(terrainSource,'function sampleField('));
const mainSource = readSrc('public', 'js', 'main.js');
const deckMatch = /const DECK_UNDER = ([\d.]+)/.exec(mainSource);
if (!deckMatch) throw new Error('Source deck thickness seam missing');
const slice = (first, last) => {
  const begin = biomesSource.indexOf(first, biomesSource.indexOf('export async function buildBiomes('));
  const end = biomesSource.indexOf(last, begin);
  if (begin < 0 || end <= begin) throw new Error(`Source seam missing: ${first}`);
  return biomesSource.slice(begin, end);
};
const roadAdapter = `
export function bakeNativeRoadWorld(cfg, terrain, osmRoads, osmData) {
  const center = cfg.center, mix = cfg.venue?.mix || null, season = cfg.env?.season || 'summer';
  const regionCenter = mapSourceCenter(cfg, 'regional');
  const regionLocation = { lat:regionCenter.lat, lng:regionCenter.lng, venue:cfg.venue, country:cfg.venue?.country,
    region:isRandomMap(cfg) ? cfg.gen.layers.regional.culture : null };
  const sceneSeed = ((Math.round(center.lat * 1e4) * 31 + Math.round(center.lng * 1e4)) ^ (cfg.gen?.seed || 0)) >>> 0;
  terrain.regionCenter = regionCenter; terrain.venue = cfg.venue || null; terrain.mix = mix;
  terrain.forestEnv = cfg.env?.forest || cfg.venue?.forest || {};
  terrain.objectEnvironment = {...terrain.forestEnv,...cfg.env,latitude:regionCenter.lat};
  const rnd = mulberry32((Math.round(center.lat * 1e4) * 31 + Math.round(center.lng * 1e4)) ^ ((cfg.teamSize || 5) << 20));
  const { blocked, towerBase, rings } = buildClearance(cfg, center);
  const basesW = ['SWARM','STEEL'].map(side => { const [x,z] = llToWorld(...cfg.bases[side], center); return {side,x,z}; });
  ${slice('  let architectureAt =', '  // 行人語意')}
  ${slice('  const pedestrianPlan =', '  const towerPoint =')}
  ${slice('  const strucDrop =', '  const bakedText =')}
  ${slice('  const tunnelRuns =', '  const vegTarget =')}
  const group = new THREE.Group();
  const roadRes = buildRoads(group, roadInput, terrain, center, mix, rnd, season, [], true, gradeCorridors,
    { controls: osmData?.roadFurniture || [], roads: roadInput });
  if (laneWetWays.length) {
    const laneRes = buildRoads(group, laneWetWays, terrain, center, mix, rnd, season, [], true, gradeCorridors);
    for (const key of ['decks','tunnels','cols']) roadRes[key].push(...laneRes[key]);
  }
  return { group, roadRes, gradeCorridors, roofThickness:TUN.ROOF_T };
}
`;
const fixtures = [];
for (const directory of ['test/fixtures/osm', 'test/fixtures/venue_roads']) {
  const folder = join(source, directory);
  for (const name of (await readdir(folder)).filter(name => /\.json(?:\.gz)?$/.test(name))) {
    const capture = readOsmCapture(join(folder, name));
    const elevation = loadElevationFixture(capture.data.name, join(folder, 'elevation'), { validate: false });
    if (!elevation || !Array.isArray(capture.data.responses?.roads?.elements)) continue;
    const valid = validateElevationFixture(elevation, { dir: join(folder, 'elevation') });
    if (!valid.ok) throw new Error(`${name}: ${valid.errors.join(', ')}`);
    const tiles = elevation.source.tiles.map(tile => ({ ...tile,
      image: decode(readFileSync(join(folder, 'elevation', tile.path))) }));
    const xs = tiles.map(tile => tile.x), ys = tiles.map(tile => tile.y);
    const bounds = { z: elevation.source.zoom, tx0: Math.min(...xs), ty0: Math.min(...ys),
      cols: Math.max(...xs) - Math.min(...xs) + 1, rows: Math.max(...ys) - Math.min(...ys) + 1 };
    if (tiles.length !== bounds.cols * bounds.rows) throw new Error(`${name}: incomplete tile mosaic`);
    fixtures.push({ capture, elevation, bounds, mosaic: mosaicOf(tiles, bounds), directory });
  }
}
const chromium = await chromiumOrNull();
if (!chromium) throw new Error('Source migration requires an available development Playwright runtime');
const server = await serve(18765);
const browser = await chromium.launch({ headless: true });
const reuse=process.argv.includes('--reuse');
const selected = process.argv.slice(2).filter(arg=>arg!=='--reuse');
const maps = JSON.parse(await readFile(join(root, 'data/maps.json'), 'utf8')).filter(map => !selected.length || selected.includes(map.id));
if (!maps.length) throw new Error('No matching map IDs');
await mkdir(join(root, 'data/worlds'), { recursive: true });
try {
  const page = await browser.newPage();
  page.on('pageerror', error => console.error('SOURCE_ERROR', error.message));
  page.on('requestfailed', request => {
    if(new URL(request.url()).origin === new URL(server.url).origin) console.error('SOURCE_FETCH',request.url(),request.failure()?.errorText);
  });
  await page.route('**/*', async route => {
    const url = route.request().url();
    if (url.endsWith('/__godot_bake')) return route.fulfill({ contentType: 'text/html', body:
      '<html><head><script type="importmap">{"imports":{"three":"https://unpkg.com/three@0.160.0/build/three.module.js","three/addons/":"https://unpkg.com/three@0.160.0/examples/jsm/"}}</script></head></html>' });
    if (url.endsWith('/js/biomes.js')) return route.fulfill({ contentType: 'text/javascript', body: biomesSource + roadAdapter });
    if (url.endsWith('/js/terrain.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineTerrainSource });
    if (url.endsWith('/build/three.module.js')) return route.fulfill({ contentType: 'text/javascript', body: await readFile(join(source, 'out/forest_review/three.module.js')) });
    const addon = /\/examples\/jsm\/(.*\.js)$/.exec(url);
    if (addon) {
      const cached = join(source, 'out/forest_review', addon[1].replaceAll('/', '_'));
      try { return await route.fulfill({ contentType:'text/javascript', body:await readFile(cached) }); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    if (new URL(url).origin === new URL(server.url).origin && new URL(url).pathname.startsWith('/js/')) {
      return route.fulfill({contentType:'text/javascript', body:await readFile(join(source,'public',new URL(url).pathname))});
    }
    if (new URL(url).origin === new URL(server.url).origin || url.startsWith('https://unpkg.com/three@0.160.0/')) return route.continue();
    return route.abort();
  });
  await page.goto(server.url + '__godot_bake');
  await page.evaluate(async () => {
    window.sourceModules = {
      terrain: await import('/js/terrain.js'), data: await import('/js/data.js'),
      cache: await import('/js/geocache.js'), biomes: await import('/js/biomes.js'),
      THREE: await import('three'), layers: await import('/js/mapLayerSources.js'),
    };
  });
  for (const map of maps) {
    const candidates = fixtures.filter(fixture => fixture.capture.data.venue?.id === map.id);
    const cfg = map.variants['5'].config;
    const rect = d.battleRect(cfg);
    const covered = fixture => {
      const { bounds, mosaic } = fixture;
      for (const x of [rect.minX, rect.maxX]) for (const z of [rect.minZ, rect.maxZ]) {
        const [lat, lng] = d.xzToLL(x, z, cfg.center);
        const px = ((lng + 180) / 360 * 2 ** bounds.z - bounds.tx0) * 256;
        const py = ((1 - Math.log(Math.tan(lat * Math.PI / 180) + 1 / Math.cos(lat * Math.PI / 180)) / Math.PI) / 2 * 2 ** bounds.z - bounds.ty0) * 256;
        if (px < 0 || py < 0 || px >= mosaic.w - 1 || py >= mosaic.h - 1) return false;
      }
      return true;
    };
    let fixture = candidates.find(covered);
    if (!fixture) {
      if(!candidates.length) throw new Error(`${map.id}: original road capture missing`);
      const outputDir=join(root,'data/source_elevation');
      let elevation=loadElevationFixture(map.id,outputDir);
      if(!elevation) {
        console.log(`${map.id}: capturing complete current-frame Terrarium tiles`);
        await captureElevationFixture({name:map.id,venue:{id:map.id,name:map.name},team:5,
          bbox:d.battleBBox(cfg),center:cfg.center,bounds:rect,outputDir,timeoutMs:15000});
        elevation=loadElevationFixture(map.id,outputDir);
      }
      if(!elevation) throw new Error(`${map.id}: new elevation capture failed validation`);
      const tiles=elevation.source.tiles.map(tile=>({...tile,image:decode(readFileSync(join(outputDir,tile.path)))}));
      const xs=tiles.map(tile=>tile.x),ys=tiles.map(tile=>tile.y);
      const bounds={z:elevation.source.zoom,tx0:Math.min(...xs),ty0:Math.min(...ys),
        cols:Math.max(...xs)-Math.min(...xs)+1,rows:Math.max(...ys)-Math.min(...ys)+1};
      fixture={...candidates[0],elevation,bounds,mosaic:mosaicOf(tiles,bounds)};
      if(!covered(fixture)) throw new Error(`${map.id}: new verified tiles still do not cover the current frame`);
    }
    const raw = new Float32Array(d.TERRAIN.GRID_N ** 2);
    for (let i = 0; i < d.TERRAIN.GRID_N; i++) for (let j = 0; j < d.TERRAIN.GRID_N; j++) {
      const x = rect.minX + (rect.maxX - rect.minX) * j / (d.TERRAIN.GRID_N - 1);
      const z = rect.minZ + (rect.maxZ - rect.minZ) * i / (d.TERRAIN.GRID_N - 1);
      raw[i * d.TERRAIN.GRID_N + j] = sampler(fixture.mosaic, fixture.bounds, ...d.xzToLL(x, z, cfg.center));
    }
    const roads = osmRoadsFromElements(fixture.capture.data.responses.roads.elements);
    const features = fixture.capture.data.responses.features?.elements;
    const osm = features ? parseOsmFeatureElements(features).pointFeatures : {};
    for (const size of [1, 2, 3, 4, 5]) {
      const target = join(root,'data/worlds',`${map.id}_${size}.json`);
      const provenance = {
        capture: basename(fixture.capture.data.name), captureSha256: fixture.capture.sha256,
        tiles: fixture.elevation.source.tiles.map(({url,sha256}) => ({url,sha256})),
        terrainSha256: sha256(terrainSource), roadsSha256: sha256(biomesSource),
        configSha256: sha256(JSON.stringify(map.variants[String(size)].config)),
        generatorSha256, inputs: sourceInputs,
      };
      provenance.fingerprint = sha256(JSON.stringify(provenance));
      if(reuse) {
        let previous;
        try { previous=JSON.parse(await readFile(target,'utf8')); }
        catch(error){if(error.code!=='ENOENT')throw error;}
        if(previous && previous.probes.every(probe=>Object.hasOwn(probe,'collisionGround'))
          && previous.source.fingerprint === provenance.fingerprint) {
          const deckAt=deckIndexOf(previous.decks),tunnelAt=tunnelIndexOf(previous.tunnels);
          const heights=previous.sourceGridPositions.filter((_,i)=>i%3===1);
          const b=previous.bounds;
          previous.laneHeights=map.variants[String(size)].lanes.map(lane=>lane.map(([x,z])=>
            tunnelAt(x,z)?.floor ?? Math.max(fieldSample(heights,x,z,previous.grid,b.minX,b.maxX,b.minZ,b.maxZ),deckAt(x,z)??-Infinity)));
          await writeFile(target,JSON.stringify(previous));
          console.log(`${map.id}/${size}: source geometry reused`);
          continue;
        }
      }
      const bundle = await page.evaluate(async ({ cfg, raw, roads, osm }) => {
        const { terrain: terrainModule, data, cache, biomes, THREE, layers } = window.sourceModules;
        const sourceKey = layers.mapSourceKey(cfg);
        const key = cache.geoKey('elev', 1, data.battleBBox(cfg), 'n' + data.TERRAIN.GRID_N + (sourceKey ? '|' + sourceKey : ''));
        if (!await cache.geoPut(key, new Float32Array(raw))) throw new Error('Elevation cache injection failed');
        const terrain = await terrainModule.buildTerrain(cfg);
        if (terrain.usedFallback) throw new Error('Unexpected elevation fallback');
        const roadWorld = biomes.bakeNativeRoadWorld(cfg, terrain, roads, osm);
        const tunnelAt = biomes.makeTunnelIndex(roadWorld.roadRes.tunnels);
        const deckAt = biomes.makeDeckIndex(roadWorld.roadRes.decks);
        const laneHeight = (x,z) => {
          const tunnel=tunnelAt(x,z);
          return tunnel?.floor ?? Math.max(terrain.heightAt(x,z),deckAt(x,z) ?? -Infinity);
        };
        const meshes = [];
        const captureMesh = (object, label, terrainMesh = false) => {
          if (!object.isMesh || !object.geometry?.attributes?.position) return;
          object.updateWorldMatrix(true, false);
          const geometry = object.geometry.clone().applyMatrix4(object.matrixWorld);
          const index = geometry.index ? Array.from(geometry.index.array) : Array.from({length:geometry.attributes.position.count}, (_, i) => i);
          const material = Array.isArray(object.material) ? object.material[0] : object.material;
          const color = material.color || material.uniforms?.diffuse?.value || material.uniforms?.color?.value;
          meshes.push({ name: object.name || label, positions: Array.from(geometry.attributes.position.array),
            normals: geometry.attributes.normal ? Array.from(geometry.attributes.normal.array) : [],
            colors: geometry.attributes.color ? Array.from(geometry.attributes.color.array) : [], index,
            albedo: color?.isColor ? [color.r, color.g, color.b] : [1,1,1], terrain: terrainMesh,
            opacity: material.opacity ?? 1, transparent: material.transparent === true });
          geometry.dispose();
        };
        terrain.mesh.updateWorldMatrix(true, false);
        captureMesh(terrain.mesh, 'Terrain', true);
        roadWorld.group.updateMatrixWorld(true);
        roadWorld.group.traverse(object => captureMesh(object, 'Road'));
        const ground = terrain.mesh.geometry;
        const positions = Array.from(ground.attributes.position.array);
        const probes = [];
        terrain.mesh.updateWorldMatrix(true,false);
        const sourceGround = (x,z) => {
          const ray = new THREE.Raycaster(new THREE.Vector3(x,data.worldCeilY(terrain.avgH,terrain.maxH)+100,z),new THREE.Vector3(0,-1,0));
          return ray.intersectObject(terrain.mesh,false)[0]?.point.y ?? null;
        };
        for (let row = 0; row < 12; row++) for (let col = 0; col < 12; col++) {
          const x = terrain.minX + terrain.worldW * (col + .271) / 12;
          const z = terrain.minZ + terrain.worldH * (row + .413) / 12;
          probes.push({x,z,ground:terrain.heightAt(x,z),collisionGround:sourceGround(x,z)});
        }
        for (const lane of cfg.lanes) for (const ll of lane) {
          const [x,z] = data.llToXZ(...ll,cfg.center);
          probes.push({x,z,ground:terrain.heightAt(x,z),collisionGround:sourceGround(x,z)});
        }
        const result = { meshes, decks: roadWorld.roadRes.decks, tunnels: roadWorld.roadRes.tunnels,
          columns: roadWorld.roadRes.cols, probes,
          minH: terrain.minH, maxH: terrain.maxH, avgH:terrain.avgH,
          ceiling: data.worldCeilY(terrain.avgH,terrain.maxH), bounds:data.battleRect(cfg), grid:data.TERRAIN.GRID_N,
          collision:{deckThickness:0,roofThickness:roadWorld.roofThickness},
          laneHeights:cfg.lanes.map(lane=>lane.map(ll=>laneHeight(...data.llToXZ(...ll,cfg.center)))),
          sourceGridPositions:positions, sourceGridIndex:Array.from(ground.index.array) };
        for (const group of [terrain.group,roadWorld.group]) group.traverse(object => {
          object.geometry?.dispose();
          const materials = Array.isArray(object.material) ? object.material : [object.material];
          for(const material of materials) material?.dispose();
        });
        return result;
      }, { cfg: map.variants[String(size)].config, raw: Array.from(raw), roads, osm });
      bundle.collision.deckThickness=Number(deckMatch[1]);
      bundle.source = provenance;
      await writeFile(target,JSON.stringify(bundle));
      console.log(`${map.id}/${size}: ${bundle.meshes.length} meshes, ${bundle.decks.length} decks, ${bundle.tunnels.length} tunnels`);
    }
  }
} finally {
  await browser.close();
  server.close();
}
