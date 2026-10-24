import { readFile, mkdir, readdir } from 'node:fs/promises';
import {writeFixtureJson} from './fixture_json.mjs';
import {WorldSourceWriter} from './world_source_writer.mjs';
import {selectWorldBundles} from './world_selection.mjs';
import { readFileSync } from 'node:fs';
import { join, resolve, basename, relative, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';
import { captureClimbBundle } from './climb_capture.mjs';
import { captureSupportBundle, prepareSceneryCapture } from './support_capture.mjs';
import { captureTextureImage, describeSourceTexture, captureTextureUV } from './texture_capture.mjs';
import { captureTrainBundle } from './train_capture.mjs';
import { readTrainRules } from './train_references.mjs';
import { instrumentSceneryMotion, captureSceneryMotion } from './scenery_motion_capture.mjs';
import { instrumentWildlifeCapture, captureWildlifeBundle } from './wildlife_capture.mjs';
import { instrumentPetalCapture, capturePetalBundle } from './petal_capture.mjs';
import { sourceSlabUpload, acceptedSourceSlabs } from './structure_references.mjs';
import { instrumentAquaticCapture, captureAquaticBundle } from './aquatic_capture.mjs';
import { instrumentMarineCapture, captureMarineBundle, captureMarineMaterial } from './marine_capture.mjs';
import { captureMarineShader } from './marine_shader_capture.mjs';
import { captureOutlineUniforms } from './outline_capture.mjs';
import { createCelCapture } from './cel_capture.mjs';
import { minimapCanvasSize } from './minimap_references.mjs';
import { instrumentWorldTextCapture, captureWorldTextMesh } from './world_text_capture.mjs';
import { createHash } from 'node:crypto';

// Source execution is confined to migration; saved meshes and collision metadata run natively.
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const source = resolve(process.env.SVS_SOURCE || join(root, '..', 'steel_vs_swarm'));
const sha256 = value => createHash('sha256').update(value).digest('hex');
const sourceAssets = new Map();
const assetHash = async name => {
  const target = resolve(source, name), path = relative(source,target);
  if (isAbsolute(path) || path === '..' || path.startsWith('..\\') || path.startsWith('../') || !name.startsWith('public/'))
    throw new Error('Invalid source asset path: ' + name);
  try { return sha256(await readFile(target)); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
};
const assetsMatch = async assets => {
  if (!assets || typeof assets !== 'object' || Array.isArray(assets)) return false;
  for (const [name,hash] of Object.entries(assets)) if (await assetHash(name) !== hash) return false;
  return true;
};
const sourceInputs = {};
for (const name of (await readdir(join(source, 'public/js'))).filter(name => name.endsWith('.js')).sort()) {
  sourceInputs[`public/js/${name}`] = sha256(await readFile(join(source, 'public/js', name)));
}
for (const name of ['public/index.html', 'server/sim.js', 'tools/elevation_fixture.mjs', 'tools/osm_fixture.mjs', 'tools/venue_field.mjs', 'out/forest_review/three.module.js']) {
  sourceInputs[name] = sha256(await readFile(join(source, name)));
}
for (const name of (await readdir(join(source,'out/forest_review'))).filter(name=>name.endsWith('.js')).sort())
  sourceInputs['out/forest_review/'+name] = sha256(await readFile(join(source,'out/forest_review',name)));
const generatorSha256 = sha256((await readFile(fileURLToPath(import.meta.url), 'utf8')) + '\n' + captureClimbBundle.toString() + '\n' + captureSupportBundle.toString() + '\n' + prepareSceneryCapture.toString() + '\n' + captureTextureImage.toString() + '\n' + describeSourceTexture.toString() + '\n' + captureTextureUV.toString() + '\n' + captureTrainBundle.toString() + '\n' + readTrainRules.toString() + '\n' + instrumentSceneryMotion.toString() + '\n' + captureSceneryMotion.toString() + '\n' + instrumentWildlifeCapture.toString() + '\n' + captureWildlifeBundle.toString() + '\n' + instrumentPetalCapture.toString() + '\n' + capturePetalBundle.toString() + '\n' + sourceSlabUpload.toString() + '\n' + acceptedSourceSlabs.toString() + '\n' + instrumentAquaticCapture.toString() + '\n' + captureAquaticBundle.toString() + '\n' + instrumentMarineCapture.toString() + '\n' + captureMarineBundle.toString() + '\n' + captureMarineMaterial.toString() + '\n' + captureMarineShader.toString() + '\n' + captureOutlineUniforms.toString() + '\n' + createCelCapture.toString() + '\n' + instrumentWorldTextCapture.toString() + '\n' + captureWorldTextMesh.toString());
const load = file => import(pathToFileURL(join(source, file)).href);
const d = await load('public/js/data.js');
const campaignMaps = JSON.parse(await readFile(join(root, 'data/campaign.json'), 'utf8')).maps;
const worldCatalog = [...JSON.parse(await readFile(join(root, 'data/maps.json'), 'utf8')), ...campaignMaps];
const bundleSelection = selectWorldBundles(worldCatalog, Object.keys(d.ENV.seasons), process.argv.slice(2));
if (process.argv.includes('--list-bundles')) {
  console.log(JSON.stringify([...bundleSelection.keys()]));
  process.exit(0);
}
const maps = [...new Map([...bundleSelection.values()].map(value => [value.map.id, value.map])).values()];
const {BattleSim} = await load('server/sim.js');
const { readSrc, grabFn, grabBlock, grabMethod } = await load('tools/audit_src.mjs');
const minimapBakeMethod = grabMethod(readSrc('public','js','game.js'),'_bakeMmBase');
const minimapSize = await minimapCanvasSize(source);
const minimapCanvasSourceSha = sha256(minimapCanvasSize.toString());
const { loadElevationFixture, validateElevationFixture, readOsmCapture } = await load('tools/osm_fixture.mjs');
const { osmRoadsFromElements, parseOsmFeatureElements } = await load('public/js/osmQuery.js');
const { chromiumOrNull, chromePath } = await load('tools/pw.mjs');
const {captureElevationFixture}=await load('tools/elevation_fixture.mjs');
const elevationSource = readSrc('tools', 'elevation_fixture.mjs');
const decode = new Function('inflateSync', `${grabFn(elevationSource, 'decodePng')}\nreturn decodePng;`)(inflateSync);
const mosaicOf = new Function(`${grabFn(elevationSource, 'makeMosaic')}\nreturn makeMosaic;`)();
const projection = elevationSource.slice(elevationSource.indexOf('const d2r ='), elevationSource.indexOf('const sha256 ='));
const sampler = new Function(`${projection}\n${grabFn(elevationSource, 'sampleMosaic')}\nreturn sampleMosaic;`)();
const biomesSource = readSrc('public', 'js', 'biomes.js');
const offlineWorldTextSource = instrumentWorldTextCapture(readSrc('public','js','worldtext.js'));
const trainRules = readTrainRules(biomesSource,await readFile(join(source,'out/forest_review/three.module.js'),'utf8'));
const trainSeam = 'let s = Math.random() * line.total, dirn = 1;';
if (!biomesSource.includes(trainSeam)) throw new Error('Original train initialization seam missing');
const groundSource = readSrc('public', 'js', 'ground.js');
const wildlifeSources = instrumentWildlifeCapture(biomesSource, readSrc('public','js','wildlifeRender.js'), groundSource, true);
const groundReturnSeam = 'border: bStat, bufCells, orphans: orphanQuads, bandDryAt };';
const bandInstallSeam = 'group.userData.bandDryAt = ground.bandDryAt;';
if (!groundSource.includes(groundReturnSeam) || !biomesSource.includes(bandInstallSeam))
  throw new Error('Original completed-scene border-mask capture seams missing');
const offlineGroundSource = wildlifeSources.ground.replace(groundReturnSeam,
  'border: bStat, bufCells, orphans: orphanQuads, bandDryAt, nativeBandMask: {cell:BSC,halfWidthMax:BD_HW_MAX,grid:Object.fromEntries(bdGrid)} };');
const buildingBatchSeam = 'const bldMeshes = group.children.slice(bldStart);';
const landmarkInstallSeam = 'group.userData.mapBuildings = registerMapBuildings(group, blockers, osmRoofPlatforms, osmBuildingMeshes, landmarkG);';
if (!biomesSource.includes(buildingBatchSeam) || !biomesSource.includes(landmarkInstallSeam))
  throw new Error('Original scenery clearance ownership seams missing');
const motionSources = instrumentSceneryMotion(wildlifeSources.biomes, readSrc('public','js','partMotion.js'));
const offlineBiomesSource = instrumentPetalCapture(motionSources.biomes, grabFn).replace(bandInstallSeam,
  bandInstallSeam + '\n  group.userData.nativeBandMask = ground.nativeBandMask;')
  .replace(buildingBatchSeam, buildingBatchSeam + '\n  group.userData.nativeCampBuildingMeshes = bldMeshes;')
  .replace(landmarkInstallSeam, landmarkInstallSeam + '\n  group.userData.nativeCampLandmarks = landmarkG;')
  .replace(trainSeam, trainSeam + '\n  train.userData.nativeTrain = {points:line.pts.map(point=>point.toArray()),total:line.total,speed,start:s,...' + JSON.stringify(trainRules) + '};');
const terrainSource=readSrc('public','js','terrain.js');
const offlineToonSource = instrumentMarineCapture(readSrc('public','js','toon.js'));
const offlineAquaticSource = instrumentAquaticCapture(readSrc('public','js','aquatics.js'), grabFn);
const imagerySeam = 'async function fetchImagery(bbox, onProgress) {';
if (!terrainSource.includes(imagerySeam)) throw new Error('Source imagery fallback seam missing');
// No imagery is captured offline; invoke the source's actual missing-service fallback.
let offlineTerrainSource = terrainSource.replace(imagerySeam,
  `${imagerySeam}\nthrow new Error('Offline geometry bake omits imagery');`);
const dryBandSeam = 'dryBand = (px, pz) => distToSegs(px, pz, segs) <= BAND_R;';
if (!offlineTerrainSource.includes(dryBandSeam) || !offlineTerrainSource.includes('inDryBand: dryBand,')) {
  throw new Error('Original terrain dry-band capture seams missing');
}
offlineTerrainSource = offlineTerrainSource.replace('let dryBand = null;', 'let dryBand = null; let nativeDryBandSpec = {segments:[],radius:0};')
  .replace(dryBandSeam, `nativeDryBandSpec = {segments:segs,radius:BAND_R}; ${dryBandSeam}`)
  .replace('inDryBand: dryBand,', 'inDryBand: dryBand, nativeDryBandSpec, nativeTideMeshes: [waterMesh,wRingMesh].filter(Boolean),');
const {TUN}=await load('tools/venue_field.mjs');
const deckIndexOf=new Function(`${grabFn(biomesSource,'makeDeckIndex')}\nreturn makeDeckIndex;`)();
const roofSource=biomesSource.split('\n').find(line=>line.startsWith('const tunRoofTop ='));
if(!roofSource) throw new Error('Source roof seam missing');
const tunnelIndexOf=new Function('TUN',`${roofSource}\n${grabFn(biomesSource,'makeTunnelIndex')}\nreturn makeTunnelIndex;`)(TUN);
const fieldSample=new Function('field','x','z','N','minX','maxX','minZ','maxZ',grabBlock(terrainSource,'function sampleField('));
const mainSource = readSrc('public', 'js', 'main.js');
const uploadSlabs = sourceSlabUpload(mainSource);
const simSource = readSrc('server', 'sim.js');
const deckMatch = /const DECK_UNDER = ([\d.]+)/.exec(mainSource);
if (!deckMatch) throw new Error('Source deck thickness seam missing');
const worldAdapter = `
import {hgtEnc as nativeHeightEncoding} from './data.js';
export async function bakeNativeWorld(cfg, terrain, osmRoads, osmData) {
  clearOsmIn();
  commitOsmIn(terrain.bbox, {feats:osmData,roads:osmRoads});
  if (!osmInReady(terrain.bbox)) throw new Error('Original world source input was not finalized');
  const group = await buildBiomes(cfg, terrain, progress => console.log('SOURCE_WORLD_CAPTURE scenery-progress '+progress));
  terrain.inBorderBand = group.userData.bandDryAt || null;
  terrain.blockers = group.userData.blockers;
  if (!Array.isArray(terrain.blockers)) throw new Error('Missing completed original scenery blockers');
  if (terrain.blockers.length > LOS.MAX_OCC) terrain.blockers.splice(LOS.MAX_OCC);
  terrain.stampSeaBlockers?.(terrain.blockers);
  return {group,roadRes:{decks:group.userData.decks,tunnels:group.userData.tunnels,cols:terrain.blockers},
    gradeCorridors:group.userData.gradeCorridors,roofThickness:TUN.ROOF_T};
}
${grabFn(mainSource, 'bakeWetGrid')}
export const bakeNativeWetGrid = bakeWetGrid;
export function bakeNativeHeightGrid(terrain) {
  const hgtEnc = nativeHeightEncoding;
  ${grabFn(mainSource, 'bakeHeightGrid')}
  return bakeHeightGrid(terrain);
}
`;
const fixtures = [];
for (const folder of [join(source, 'test/fixtures/osm'), join(source, 'test/fixtures/venue_roads'), join(root, 'data/source_campaign')]) {
	let files;
	try { files = await readdir(folder); }
	catch(error) { if(error.code==='ENOENT'&&folder.startsWith(root))continue;throw error; }
  for (const name of files.filter(name => /\.json(?:\.gz)?$/.test(name))) {
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
    fixtures.push({ capture, elevation, bounds, mosaic: mosaicOf(tiles, bounds), directory:folder });
  }
}
const chromium = await chromiumOrNull();
if (!chromium) throw new Error('Source migration requires an available development Playwright runtime');
const sourceOrigin = 'http://godot-worlds.invalid';
console.log('SOURCE_WORLD_CAPTURE browser-starting');
const browser = await chromium.launch({ headless: true, executablePath: chromePath(), args:['--js-flags=--max-old-space-size=8192'] });
console.log('SOURCE_WORLD_CAPTURE browser-started');
const reuse=process.argv.includes('--reuse');
await mkdir(join(root, 'data/worlds'), { recursive: true });
let worldMeshWriter=null;
try {
  const page = await browser.newPage();
  await page.addInitScript({content:'globalThis.__sourceWorldTextCapture = ('+captureWorldTextMesh.toString()+');'});
  let worldSections = Object.create(null);
  await page.exposeFunction('__sourceWorldMesh', async (operation,index,offset,json) => {
    if(!Number.isInteger(index)||index<0||!Number.isInteger(offset)||offset<0||typeof json!=='string')
      throw new Error('Invalid original world mesh transfer');
    if(operation==='begin') {
      if(offset!==0)throw new Error('Out-of-order original world mesh');
      const captured=JSON.parse(json);
      await worldMeshWriter.begin(index,captured.header,captured.lengths);
    } else if(operation==='array') {
      await worldMeshWriter.part(index,offset,JSON.parse(json));
    } else if(operation==='end') {
      if(offset!==0)throw new Error('Invalid original world mesh boundary');
      await worldMeshWriter.end(index);
    } else throw new Error('Unknown original world mesh transfer operation');
  });
  await page.exposeFunction('__sourceWorldSection', async (key, offset, json) => {
    if(typeof key!=='string'||!/^\w+$/.test(key)||key==='__proto__'||!Number.isInteger(offset)||offset<0||typeof json!=='string')
      throw new Error('Invalid original world section transfer');
    const values=JSON.parse(json);
    if(key==='meshes') {
      if(!Array.isArray(values)||offset!==worldMeshWriter.count)throw new Error('Out-of-order original world mesh batch');
      for(const mesh of values)await worldMeshWriter.append(mesh);
      return;
    }
    const rows=worldSections[key]??=[];
    if(!Array.isArray(values)||offset!==rows.length)throw new Error('Out-of-order original world section: '+key);
    if(offset===0)console.log('SOURCE_WORLD_CAPTURE receiving '+key);
    for(const value of values)rows.push(value);
  });
  page.once('crash', () => {
    console.error('SOURCE_WORLD_CAPTURE renderer-crashed');
    void browser.close().catch(error=>console.error('SOURCE_WORLD_CAPTURE browser-close-failed',error.message));
  });
  page.on('console', message => {
    if(message.text().startsWith('SOURCE_WORLD_CAPTURE '))console.log(message.text());
  });
  page.on('pageerror', error => console.error('SOURCE_ERROR', error.message));
  page.on('requestfailed', request => {
    if(new URL(request.url()).origin === sourceOrigin) console.error('SOURCE_FETCH',request.url(),request.failure()?.errorText);
  });
  await page.route('**/*', async route => {
    const url = route.request().url();
    try {
    if (url.endsWith('/__godot_bake')) return route.fulfill({ contentType: 'text/html', body:
      '<html><head><script type="importmap">{"imports":{"three":"https://unpkg.com/three@0.160.0/build/three.module.js","three/addons/":"https://unpkg.com/three@0.160.0/examples/jsm/"}}</script></head></html>' });
    if (url.endsWith('/js/biomes.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineBiomesSource + worldAdapter });
    if (url.endsWith('/js/worldtext.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineWorldTextSource });
    if (url.endsWith('/js/ground.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineGroundSource });
    if (url.endsWith('/js/partMotion.js')) return route.fulfill({ contentType: 'text/javascript', body: motionSources.parts });
    if (url.endsWith('/js/wildlifeRender.js')) return route.fulfill({ contentType: 'text/javascript', body: wildlifeSources.render });
    if (url.endsWith('/js/aquatics.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineAquaticSource });
    if (url.endsWith('/js/terrain.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineTerrainSource });
    if (url.endsWith('/js/toon.js')) return route.fulfill({ contentType: 'text/javascript', body: offlineToonSource });
    if (url.endsWith('/build/three.module.js')) return route.fulfill({ contentType: 'text/javascript', body: await readFile(join(source, 'out/forest_review/three.module.js')) });
    const addon = /\/examples\/jsm\/(.*\.js)$/.exec(url);
    if (addon) {
      const cached = join(source, 'out/forest_review', addon[1].replaceAll('/', '_'));
      try { return await route.fulfill({ contentType:'text/javascript', body:await readFile(cached) }); }
      catch (error) { throw new Error('Missing original cached Three addon: '+cached,{cause:error}); }
    }
    if (new URL(url).origin === sourceOrigin && new URL(url).pathname.startsWith('/js/')) {
      return route.fulfill({contentType:'text/javascript', body:await readFile(join(source,'public',new URL(url).pathname))});
    }
    if (new URL(url).origin === sourceOrigin && new URL(url).pathname.startsWith('/assets/')) {
      const name = 'public/' + decodeURIComponent(new URL(url).pathname.slice(1));
      sourceAssets.set(name,await assetHash(name));
      const hash = sourceAssets.get(name);
      if (hash === null) return route.fulfill({status:404,body:''});
      const extension = name.split('.').at(-1).toLowerCase();
      const contentType = {png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',webp:'image/webp',svg:'image/svg+xml',gltf:'model/gltf+json',glb:'model/gltf-binary'}[extension] || 'application/octet-stream';
      return route.fulfill({contentType,body:await readFile(resolve(source,name))});
    }
    return route.abort();
    } catch(error) {
      console.error('SOURCE_WORLD_ROUTE_ERROR',url,error.message);
      return route.abort();
    }
  });
  const loadModules=async()=>{
  await page.goto(sourceOrigin + '/__godot_bake');
  console.log('SOURCE_WORLD_CAPTURE modules-starting');
  await page.evaluate(async () => {
    window.sourceModules = {
      terrain: await import('/js/terrain.js'), data: await import('/js/data.js'),
      cache: await import('/js/geocache.js'), biomes: await import('/js/biomes.js'),
      climb: await import('/js/climb.js'),
      toon: await import('/js/toon.js'),
      buildings: await import('/js/mapBuildingRender.js'),
      THREE: await import('three'), layers: await import('/js/mapLayerSources.js'),
    };
  });
  console.log('SOURCE_WORLD_CAPTURE modules-loaded');
  };
  await loadModules();
  let capturedVariants=0;
  for (const map of maps) {
    console.log('SOURCE_WORLD_CAPTURE map-starting '+map.id);
    const candidates = fixtures.filter(fixture => fixture.capture.data.venue?.id === (map.source_id || map.id));
    const sizes = Object.keys(map.variants).map(Number).sort((a,b)=>a-b);
    const cfg = map.variants[String(sizes.at(-1))].config;
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
    console.log('SOURCE_WORLD_CAPTURE elevation-ready '+map.id);
    for (let i = 0; i < d.TERRAIN.GRID_N; i++) for (let j = 0; j < d.TERRAIN.GRID_N; j++) {
      const x = rect.minX + (rect.maxX - rect.minX) * j / (d.TERRAIN.GRID_N - 1);
      const z = rect.minZ + (rect.maxZ - rect.minZ) * i / (d.TERRAIN.GRID_N - 1);
      raw[i * d.TERRAIN.GRID_N + j] = sampler(fixture.mosaic, fixture.bounds, ...d.xzToLL(x, z, cfg.center));
    }
    const roads = osmRoadsFromElements(fixture.capture.data.responses.roads.elements);
    const features = fixture.capture.data.responses.features?.elements;
    const osm = features ? parseOsmFeatureElements(features) : null;
    const seasons = map.chapter ? [map.variants[String(sizes[0])].config.env?.season || 'summer'] : Object.keys(d.ENV.seasons);
    if (seasons.some(season=>!Object.hasOwn(d.ENV.seasons,season))) throw new Error('Unsupported original map season: '+map.id);
    for (const size of sizes) for (const season of seasons) {
      if (!bundleSelection.has(`${map.id}_${size}_${season}`)) continue;
      console.log(`SOURCE_WORLD_CAPTURE variant-starting ${map.id}/${size}/${season}`);
      const worldConfig = structuredClone(map.variants[String(size)].config);
      worldConfig.env = {...worldConfig.env,season};
      const target = join(root,'data/worlds',`${map.id}_${size}_${season}.json`);
      const provenance = {
        identity:{map:map.id,teamSize:size,season},
        capture: basename(fixture.capture.data.name), captureSha256: fixture.capture.sha256,
        tiles: fixture.elevation.source.tiles.map(({url,sha256}) => ({url,sha256})),
        terrainSha256: sha256(terrainSource), roadsSha256: sha256(biomesSource),
        configSha256: sha256(JSON.stringify(worldConfig)),
        generatorSha256, selectorSha256: sha256(selectWorldBundles.toString()), minimapCanvasSourceSha, inputs: sourceInputs,
      };
      provenance.inputFingerprint = sha256(JSON.stringify(provenance));
      if(reuse) {
        let previous;
        try { previous=JSON.parse(await readFile(target,'utf8')); }
        catch(error){if(error.code!=='ENOENT')throw error;}
        if(previous && previous.minimapBase && previous.waterProfile && previous.heightField && previous.probes.every(probe=>Object.hasOwn(probe,'collisionGround'))
          && previous.source.inputFingerprint === provenance.inputFingerprint && await assetsMatch(previous.source.assets)) {
          const deckAt=deckIndexOf(previous.decks),tunnelAt=tunnelIndexOf(previous.tunnels);
          for (const [name,hash] of Object.entries(previous.source.assets)) sourceAssets.set(name,hash);
          const heights=previous.sourceGridPositions.filter((_,i)=>i%3===1);
          const b=previous.bounds;
          previous.laneHeights=map.variants[String(size)].lanes.map(lane=>lane.map(([x,z])=>
            tunnelAt(x,z)?.floor ?? Math.max(fieldSample(heights,x,z,previous.grid,b.minX,b.maxX,b.minZ,b.maxZ),deckAt(x,z)??-Infinity)));
          await writeFixtureJson(target,previous);
          console.log(`${map.id}/${size}/${season}: source geometry reused`);
          continue;
        }
      }
      worldSections=Object.create(null);
      if(capturedVariants++)await loadModules();
      worldMeshWriter=new WorldSourceWriter(join(root,'data/worlds'));
      const transfer = JSON.parse(await page.evaluate(async ({ cfg, raw, roads, osm, minimapMethod, minimapSize, climbCaptureSource, supportCaptureSource, sceneryPrepareSource, textureImageSource, textureDescriptionSource, textureUVSource, trainCaptureSource, motionCaptureSource, wildlifeCaptureSource, petalCaptureSource, aquaticCaptureSource, marineCaptureSource, marineMaterialSource, marineShaderSource, outlineCaptureSource, celCaptureSource }) => {
        const { terrain: terrainModule, data, cache, biomes, climb, buildings, THREE, layers, toon } = window.sourceModules;
        const sourceKey = layers.mapSourceKey(cfg);
        const key = cache.geoKey('elev', 1, data.battleBBox(cfg), 'n' + data.TERRAIN.GRID_N + (sourceKey ? '|' + sourceKey : ''));
        console.log('SOURCE_WORLD_CAPTURE cache-starting');
        if (!await cache.geoPut(key, new Float32Array(raw))) throw new Error('Elevation cache injection failed');
        console.log('SOURCE_WORLD_CAPTURE terrain-starting');
        const terrain = await terrainModule.buildTerrain(cfg);
        if (terrain.usedFallback) throw new Error('Unexpected elevation fallback');
        console.log('SOURCE_WORLD_CAPTURE scenery-starting');
        const roadWorld = await biomes.bakeNativeWorld(cfg, terrain, roads, osm);
        console.log('SOURCE_WORLD_CAPTURE scenery-built');
        const sourceBand=roadWorld.group.userData.bandDryAt;
        if(sourceBand!==null&&typeof sourceBand!=='function')throw new Error('Missing original border dry-band state');
        const borderBands=typeof sourceBand==='function';
        const borderMask=roadWorld.group.userData.nativeBandMask;
        if(borderBands&&(!borderMask||!(borderMask.cell>0)||!borderMask.grid))throw new Error('Missing completed original border dry mask');
        console.log('SOURCE_WORLD_CAPTURE border-bands '+borderBands);
        new Function('return (' + sceneryPrepareSource + ');')()(roadWorld.group, buildings.detachMapBuilding);
        console.log('SOURCE_WORLD_CAPTURE buildings-prepared');
        const trainBundle = new Function('return (' + trainCaptureSource + ');')()(roadWorld.group);
        const motionBundle = new Function('return (' + motionCaptureSource + ');')()(roadWorld.group);
        const wildlifeBundle = new Function('return (' + wildlifeCaptureSource + ');')()(roadWorld.group);
        const petalBundle = new Function('return (' + petalCaptureSource + ');')()(roadWorld.group);
        const aquaticBundle = new Function('return (' + aquaticCaptureSource + ');')()(roadWorld.group,terrain.waterY);
        console.log('SOURCE_WORLD_CAPTURE animation-captured');
        const tunnelAt = biomes.makeTunnelIndex(roadWorld.roadRes.tunnels);
        const deckAt = biomes.makeDeckIndex(roadWorld.roadRes.decks);
        const laneHeight = (x,z) => {
          const tunnel=tunnelAt(x,z);
          return tunnel?.floor ?? Math.max(terrain.heightAt(x,z),deckAt(x,z) ?? -Infinity);
        };
        const meshes = [], textureImages = [], textureIds = new Map();
        let meshCount=0;
        const flushMeshes=async()=>{
          if(!meshes.length)return;
          for(const mesh of meshes){
            if(meshCount<16||mesh.positions.length>1000000)console.log('SOURCE_WORLD_CAPTURE mesh-transfer '+JSON.stringify({index:meshCount,name:mesh.name,positions:mesh.positions.length,instances:mesh.instances?.length||0}));
            const arrays=[];
            const header=JSON.parse(JSON.stringify(mesh,(_key,value)=>{
              if(value&&typeof value==='object'&&Object.hasOwn(value,'$sourceArray'))throw new Error('Reserved source mesh transfer property');
              if(Array.isArray(value)&&value.length>4096){arrays.push(value);return {$sourceArray:arrays.length-1};}
              return value;
            }));
            await window.__sourceWorldMesh('begin',meshCount,0,JSON.stringify({header,lengths:arrays.map(values=>values.length)}));
            for(let id=0;id<arrays.length;id++){
              const values=arrays[id],size=typeof values[0]==='number'?65536:64;
              for(let offset=0;offset<values.length;offset+=size)
                await window.__sourceWorldMesh('array',id,offset,JSON.stringify(values.slice(offset,offset+size)));
            }
            await window.__sourceWorldMesh('end',meshCount,0,'');
            meshCount++;
          }
          meshes.length=0;
        };
        const encodeTextureImage = new Function('return (' + textureImageSource + ');')();
        const MinimapSource = new Function('return class {' + minimapMethod + '};')();
        const minimap = new MinimapSource();minimap.terrain=terrain;
        const minimapCanvas = minimap._bakeMmBase(...minimapSize);
        const minimapBase = {image:textureImages.length,width:minimapCanvas.width,height:minimapCanvas.height,imagery:!!terrain.sampleColor};
        textureImages.push(encodeTextureImage({image:minimapCanvas},false));
        const describeTexture = new Function('return (' + textureDescriptionSource + ');')();
        const captureUV = new Function('return (' + textureUVSource + ');')();
        const textureDescription = texture => {
          if(!texture)throw new Error('Missing original shader texture uniform');
          let captured=texture;
          if(texture.format===THREE.RedFormat) {
            const image=texture.image;
            if(!(image?.data instanceof Uint8Array)||image.data.length!==image.width*image.height)
              throw new Error('Unsupported original single-channel shader texture');
            const rgba=new Uint8Array(image.data.length*4);
            for(let i=0;i<image.data.length;i++){rgba[i*4]=image.data[i];rgba[i*4+3]=255;}
            captured=texture.clone();
            captured.source=new THREE.Source({width:image.width,height:image.height,data:rgba});
            captured.format=THREE.RGBAFormat;
          }
          if (!textureIds.has(texture)) {
            textureIds.set(texture,textureImages.length);
            textureImages.push(encodeTextureImage(captured,true));
          }
          const description={...describeTexture(captured,THREE),image:textureIds.get(texture)};
          if(captured!==texture)captured.dispose();
          return description;
        };
        const marineBundle = new Function('return (' + marineCaptureSource + ');')()(toon,textureDescription);
        const marineMaterial = new Function('return (' + marineMaterialSource + ');')();
        const marineShader = new Function('return (' + marineShaderSource + ');')();
        const captureOutline = new Function('return (' + outlineCaptureSource + ');')();
        const cel = new Function('return (' + celCaptureSource + ');')()(THREE,textureDescription,texture=>describeTexture(texture,THREE,true));
        const marineParts = toon.nativeMarineUniforms().program;
        const marinePrograms = [], marineMaterials = new WeakMap();
        const captureMarine = material => {
          if(!marineMaterials.has(material))marineMaterials.set(material,marineMaterial(material,shader=>{
            const code=marineShader(shader,marineParts);
            let index=marinePrograms.indexOf(code);
            if(index<0){index=marinePrograms.length;marinePrograms.push(code);}
            return index;
          },textureDescription));
          return marineMaterials.get(material);
        };
        const materialDescription = material => {
          const color = material.color || material.uniforms?.diffuse?.value || material.uniforms?.color?.value;
          const marine = captureMarine(material);
          const celMaterial=cel.capture(material);
          return {albedo:color?.isColor ? color.toArray() : [1,1,1],opacity:material.opacity ?? 1,
            ...(celMaterial?{cel:celMaterial}:{}),
            ...(marine ? {marine} : {}),
            ...(color?.isColor ? {albedoHex:color.getHex()} : {}),
            transparent:material.transparent === true,unshaded:!!material.isMeshBasicMaterial,
            vertexColors:!!material.vertexColors,depthWrite:material.depthWrite !== false,depthTest:material.depthTest !== false,
            side:material.side,alphaTest:material.alphaTest || 0,blending:material.blending,
            roughness:material.roughness ?? .95,metalness:material.metalness ?? 0,
            ...(material.map ? {texture:textureDescription(material.map)} : {}),
            emission:material.emissive?.toArray() || [0,0,0],emissionHex:material.emissive?.getHex() || 0,emissionIntensity:material.emissiveIntensity ?? 1};
        };
        const attributeValues = (geometry, name) => {
          const attribute = geometry.getAttribute(name);
          if (!attribute) return [];
          if (attribute.itemSize > 4) throw new Error('Unsupported original world attribute: ' + name);
          const getters = ['getX','getY','getZ','getW'].slice(0,attribute.itemSize);
          const values = Array.from({length:attribute.count},(_,i)=>getters.map(getter=>attribute[getter](i))).flat();
          if (!values.every(Number.isFinite)) throw new Error('Non-finite original world attribute: ' + name);
          return values;
        };
        const captureMesh = (object, label, terrainMesh = false, flags = {}) => {
          if (!object.isMesh || !object.geometry?.attributes?.position) return;
		  const worldText=globalThis.__sourceWorldTextCapture(object);
		  if(worldText)flags.sourceWorldText=worldText;
			if(object.isInstancedMesh&&object.geometry.attributes.seaFade)
				throw new Error('Original instanced water needs its exact instance-aware shader capture');
          object.updateWorldMatrix(true, false);
          let visible = true, motionRoot = null;
          for (let parent = object; parent; parent = parent.parent) {
            visible = visible && parent.visible;
            if (parent.userData.nativeBuildingKey) flags.sourceBuildingKey = parent.userData.nativeBuildingKey;
            if (parent.userData.nativeCampLandmark) flags.sourceCampLandmark = parent.userData.nativeCampLandmark;
            if (parent.userData.nativeWildlifeMesh) flags.sourceWildlifeMesh = parent.userData.nativeWildlifeMesh;
            if (parent.userData.nativePetalMesh) flags.sourcePetalMesh = parent.userData.nativePetalMesh;
            if (parent.userData.nativeAquaticMesh) flags.sourceAquaticMesh = parent.userData.nativeAquaticMesh;
            if (!motionRoot && parent.userData.nativeMotionId) {motionRoot=parent;flags.sourceMotionId=parent.userData.nativeMotionId;}
            if (!motionRoot && parent.userData.nativeTrainId) {motionRoot=parent;flags.sourceTrainId=parent.userData.nativeTrainId;}
          }
          const geometryFrame = motionRoot ? motionRoot.matrixWorld.clone().invert().multiply(object.matrixWorld) : object.matrixWorld;
          if (object.geometry.attributes.aReflO && !geometryFrame.equals(new THREE.Matrix4()))
            throw new Error('Original encoded water reflection requires its identity geometry frame');
          const geometry = object.geometry.clone();
          if (geometry.attributes.color && ![3,4].includes(geometry.attributes.color.itemSize))
            throw new Error('Unsupported original world color channel count');
          const outline = !!object.userData.isOutline;
          if (outline && object.isInstancedMesh) throw new Error('Original outline shell unexpectedly uses instancing');
          if (!object.isInstancedMesh && !outline) {
            for (const name of ['position','normal']) {
              const attribute = geometry.getAttribute(name);
              if (attribute && (attribute.normalized || attribute.isInterleavedBufferAttribute))
                geometry.setAttribute(name,new THREE.Float32BufferAttribute(attributeValues(geometry,name),attribute.itemSize));
            }
            geometry.applyMatrix4(geometryFrame);
          }
          const instances = [];
          const instanceColors = [];
          if (object.isInstancedMesh) for (let i = 0; i < object.count; i++) {
            const matrix = new THREE.Matrix4(); object.getMatrixAt(i, matrix);
            instances.push(geometryFrame.clone().multiply(matrix).toArray());
            if (object.instanceColor) {
              const color = new THREE.Color(); object.getColorAt(i, color); instanceColors.push(color.toArray());
            }
          }
          const index = geometry.index ? Array.from(geometry.index.array) : Array.from({length:geometry.attributes.position.count}, (_, i) => i);
          const isMaterialArray = Array.isArray(object.material);
          const materials = isMaterialArray ? object.material : [object.material];
          const drawStart = geometry.drawRange.start, drawEnd = Math.min(index.length,drawStart+geometry.drawRange.count);
          const surfaces = (isMaterialArray ? geometry.groups : [{start:0,count:index.length,materialIndex:0}]).flatMap(group=>{
            const material = materials[group.materialIndex];
            if (!material || material.visible === false) return [];
            const start = Math.max(drawStart,group.start), end = Math.min(drawEnd,group.start+group.count);
            if (end <= start) return [];
            if (start % 3 !== 0 || (end-start) % 3 !== 0) throw new Error('Unaligned original world triangle draw range');
            const triangles = index.slice(start,end);
            if (!object.isInstancedMesh && !outline && geometryFrame.determinant() < 0)
              for (let i=0;i<triangles.length;i+=3) [triangles[i+1],triangles[i+2]]=[triangles[i+2],triangles[i+1]];
            return [{...materialDescription(material),index:triangles}];
          });
          if (!surfaces.length) { geometry.dispose(); return; }
          const celGeometry=surfaces.some(surface=>surface.cel)?{frame:geometryFrame.toArray(),
            positions:attributeValues(object.geometry,'position'),normals:attributeValues(object.geometry,'normal')}:null;
          if (object.userData.nativeCampBuildingBatch) flags.sourceCampBuildingBatch = true;
          meshes.push({ name: object.name || label, positions: attributeValues(geometry,'position'),attributes:cel.attributes(object.geometry),
            normals:attributeValues(geometry,'normal'),colors:attributeValues(geometry,'color'),
            ...(geometry.attributes.seaFade ? {seaFade:attributeValues(geometry,'seaFade'),
              marinePositions:attributeValues(object.geometry,'position'),marineFrame:geometryFrame.toArray()} : {}),
            ...(geometry.attributes.aReflO ? {reflectionOrigins:attributeValues(geometry,'aReflO')} : {}),
            colorSize:geometry.attributes.color?.itemSize || 3,uv:captureUV(geometry),
            uv1:captureUV(geometry,1),uv2:captureUV(geometry,2),uv3:captureUV(geometry,3),
            ...surfaces[0],...(surfaces.length > 1 ? {surfaces} : {}),terrain: terrainMesh, water:!!geometry.attributes.seaFade,
            tideWater:terrain.nativeTideMeshes.includes(object),visible,
            castShadow:!!object.castShadow,
            receiveShadow:!!object.receiveShadow,frustumCulled:object.frustumCulled!==false,renderOrder:object.renderOrder,
            ...(outline ? {outlineUniforms:captureOutline(object.material),outlineFrame:geometryFrame.toArray()} : {}),
            ...(celGeometry?{celGeometry}:{}),
            ...(object.isInstancedMesh ? {instances} : {}), ...(object.instanceColor ? {instanceColors} : {}), ...flags });
          if((meshCount+meshes.length)%128===0)console.log('SOURCE_WORLD_CAPTURE meshes-captured '+(meshCount+meshes.length));
          geometry.dispose();
        };
        terrain.mesh.updateWorldMatrix(true, false);
        captureMesh(terrain.mesh, 'Terrain', true);
        await flushMeshes();
        const waterObjects=[];
        terrain.group.traverse(object => {
          if(object.geometry?.attributes?.seaFade)waterObjects.push(object);
        });
        for(const object of waterObjects){captureMesh(object,'Water');if(meshes.length>=16)await flushMeshes();}
        roadWorld.group.updateMatrixWorld(true);
        const sceneryObjects=[];
        roadWorld.group.traverse(object => {
          for (let parent = object; parent; parent = parent.parent) if (parent.name === 'climbRoutes') return;
          sceneryObjects.push(object);
        });
        for(const object of sceneryObjects){captureMesh(object,'Scenery');if(meshes.length>=16)await flushMeshes();}
        const climbObjects=[];
        const climbBundle = new Function('return (' + climbCaptureSource + ');')()(roadWorld.group, (...args)=>climbObjects.push(args), climb.CLIMB_ARROW);
        for(const args of climbObjects){captureMesh(...args);if(meshes.length>=16)await flushMeshes();}
        await flushMeshes();
        const {supportBlockers, ...supportBundle} = new Function('return (' + supportCaptureSource + ');')()(roadWorld.group, THREE);
        const columns = supportBundle.supportsCaptured ? supportBlockers : roadWorld.roadRes.cols;
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
        if(terrain.sampleColor) throw new Error('Source imagery classification needs its exact native capture path');
        const heightField=Array.from(new Float32Array(Array.from({length:data.TERRAIN.GRID_N**2},(_,index)=> {
          const row=Math.floor(index/data.TERRAIN.GRID_N),col=index%data.TERRAIN.GRID_N;
          return terrain.heightAt(terrain.minX+terrain.worldW*col/(data.TERRAIN.GRID_N-1),terrain.minZ+terrain.worldH*row/(data.TERRAIN.GRID_N-1));
        })));
        const waterProfile={baseY:terrain.baseWaterY,isMarine:terrain.isMarine,dryBands:terrain.nativeDryBandSpec,
          wetGrid:biomes.bakeNativeWetGrid(terrain),heightGrid:biomes.bakeNativeHeightGrid(terrain),imagery:false,borderBands,...(borderBands?{borderMask}:{})};
        const rd=value=>Math.round(value*10)/10;
        const weatherOcc=columns.slice(0,data.LOS.MAX_OCC).map(b=>b.hw2!=null
          ? [rd(b.x),rd(-b.z),rd(Math.min(60,Math.hypot(b.hw2,b.hd2))),rd(Math.min(300,b.h)),rd(b.hw2),rd(b.hd2),Math.round(-b.ry*1000)/1000,b.buildingKey||null,rd(b.y)]
          : [rd(b.x),rd(-b.z),rd(Math.min(60,b.r)),rd(Math.min(300,b.h))]);
        const weatherCor=roadWorld.gradeCorridors.slice(0,data.LOS.MAX_CORR)
          .map(c=>[rd(c.x1),rd(-c.z1),rd(c.x2),rd(-c.z2),rd(c.hw),c.kind==='tun'?1:0]);
        for(const probe of probes) probe.waterCode=biomes.terrainEnvCode(terrain,probe.x,probe.z);
        const result = { textureImages, minimapBase, marinePrograms,celPrograms:cel.programs,celSamplers:cel.samplers, ...climbBundle, ...supportBundle, ...trainBundle, ...motionBundle, ...wildlifeBundle, ...petalBundle, ...aquaticBundle, ...marineBundle, decks: roadWorld.roadRes.decks, tunnels: roadWorld.roadRes.tunnels,
          structurePads:{tower:roadWorld.group.userData.towerPads,base:roadWorld.group.userData.basePads},
          columns, probes,
          minH: terrain.minH, maxH: terrain.maxH, avgH:terrain.avgH,
          ceiling: data.worldCeilY(terrain.avgH,terrain.maxH), bounds:data.battleRect(cfg), grid:data.TERRAIN.GRID_N,
          collision:{deckThickness:0,roofThickness:roadWorld.roofThickness},
          laneHeights:cfg.lanes.map(lane=>lane.map(ll=>laneHeight(...data.llToXZ(...ll,cfg.center)))),
          sourceGridPositions:positions, sourceGridIndex:Array.from(ground.index.array),heightField,waterProfile,weatherOcc,weatherCor };
        for (const group of [terrain.group,roadWorld.group]) group.traverse(object => {
          object.geometry?.dispose();
          const materials = Array.isArray(object.material) ? object.material : [object.material];
          for(const material of materials) material?.dispose();
        });
        console.log('SOURCE_WORLD_CAPTURE bundle-built');
        const header={},counts={meshes:meshCount};
        for(const [key,values]of Object.entries(result)) {
          if(!Array.isArray(values)){header[key]=values;continue;}
          counts[key]=values.length;
          const chunkSize=['meshes','textureImages'].includes(key)?1:typeof values[0]==='number'?8192:16;
          for(let offset=0;offset<values.length;offset+=chunkSize)
            await window.__sourceWorldSection(key,offset,JSON.stringify(values.slice(offset,offset+chunkSize)));
          result[key]=null;
        }
        return JSON.stringify({header,counts});
      }, { minimapMethod: minimapBakeMethod, minimapSize, cfg: worldConfig, raw: Array.from(raw), roads, osm, climbCaptureSource: captureClimbBundle.toString(), supportCaptureSource: captureSupportBundle.toString(), sceneryPrepareSource: prepareSceneryCapture.toString(), textureImageSource: captureTextureImage.toString(), textureDescriptionSource: describeSourceTexture.toString(), textureUVSource: captureTextureUV.toString(), trainCaptureSource: captureTrainBundle.toString(), motionCaptureSource:captureSceneryMotion.toString(), wildlifeCaptureSource:captureWildlifeBundle.toString(), petalCaptureSource:capturePetalBundle.toString(), aquaticCaptureSource:captureAquaticBundle.toString(), marineCaptureSource:captureMarineBundle.toString(), marineMaterialSource:captureMarineMaterial.toString(), marineShaderSource:captureMarineShader.toString(), outlineCaptureSource:captureOutlineUniforms.toString(), celCaptureSource:createCelCapture.toString() }));
      const bundle=transfer.header;
      const storage=await worldMeshWriter.finish();
      await worldMeshWriter.dispose();
      worldMeshWriter=null;
      if(storage.meshCount!==transfer.counts.meshes)throw new Error('Incomplete original world mesh count');
      Object.assign(bundle,storage);
      for(const [key,count]of Object.entries(transfer.counts)) {
        if(key==='meshes')continue;
        const rows=worldSections[key]??[];
        if(rows.length!==count||Object.hasOwn(bundle,key))throw new Error('Incomplete original world section: '+key);
        bundle[key]=rows;
      }
      if(Object.keys(worldSections).some(key=>!Object.hasOwn(transfer.counts,key)))throw new Error('Unexpected original world section');
      worldSections=Object.create(null);
      console.log('SOURCE_WORLD_CAPTURE transfer-counts '+JSON.stringify(transfer.counts));
      bundle.collision.deckThickness=Number(deckMatch[1]);
      const rawSlabs = uploadSlabs(bundle,value=>Math.round(value*10)/10,d.LOS);
      bundle.acceptedSlabs = acceptedSourceSlabs(d,BattleSim,worldConfig,simSource,rawSlabs).entries;
      bundle.slabsCaptured = true;
      const authority=new BattleSim(worldConfig);
      // Store the unpruned original world; each live match clears its own actual camp sites.
      authority.camps=[];
      bundle.corridors=[];
      authority._pruneCorridors=cor=>{bundle.corridors=cor;};
      authority.setWorld({occ:JSON.parse(JSON.stringify(bundle.weatherOcc)),cor:bundle.weatherCor,wet:bundle.waterProfile.wetGrid,hgt:bundle.waterProfile.heightGrid,slabs:rawSlabs});
      bundle.waterProfile.obstacles=authority.worldOcc.map(shape=>({shape:Array.from(shape),baseY:shape.baseY??null,...(shape.buildingKey?{buildingKey:shape.buildingKey}:{})}));
      delete bundle.weatherOcc;
      delete bundle.weatherCor;
      provenance.assets = Object.fromEntries(Array.from(sourceAssets).sort(([a],[b])=>a.localeCompare(b)));
      provenance.fingerprint = sha256(JSON.stringify(provenance));
      bundle.source = provenance;
      await writeFixtureJson(target,bundle);
      console.log(`${map.id}/${size}/${season}: ${bundle.meshCount} meshes, ${bundle.decks.length} decks, ${bundle.tunnels.length} tunnels`);
    }
  }
} finally {
  try {await browser.close();}
  finally {await worldMeshWriter?.dispose();}
}
