import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {inflateSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {selectWorldBundles} from '../tools/world_selection.mjs';
import {worldElevationFrames,captureWorldElevation} from '../tools/world_elevation_capture.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const load=name=>import(pathToFileURL(join(source,name)).href);
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
for(const name of ['public/js/data.js','public/js/terrain.js','public/js/mapLayerSources.js'])
  assert.equal(createHash('sha256').update(await readFile(join(source,name))).digest('hex'),provenance.inputs[name]);
const d=await load('public/js/data.js'),layers=await load('public/js/mapLayerSources.js');
const {grabFn,grabBlock,readSrc}=await load('tools/audit_src.mjs');
const {loadElevationFixture,validateElevationFixture}=await load('tools/osm_fixture.mjs');
const maps=JSON.parse(await readFile(join(root,'data/maps.json'),'utf8'));
const terrain=readSrc('public','js','terrain.js');
const loopStart=terrain.indexOf('for (let i = 0; i < GRID_N; i++)',terrain.indexOf('rawElev = new Float32Array'));
assert.ok(loopStart>=0);
const original=new Function('cfg','GRID_N','battleRect','mapSourceCenter','xzToLL','sampleElev',
  `const rect=battleRect(cfg),elevCenter=mapSourceCenter(cfg,'elevation');
   const rawElev=new Float32Array(GRID_N*GRID_N);let elevationComplete=true;
   for (let i=0;i<GRID_N;i++) ${grabBlock(terrain.slice(loopStart),'for (')}
   return {rawElev,elevationComplete};`);
const elevation=readSrc('tools','elevation_fixture.mjs');
const decode=new Function('inflateSync',grabFn(elevation,'decodePng')+';return decodePng;')(inflateSync);
const makeMosaic=new Function(grabFn(elevation,'makeMosaic')+';return makeMosaic;')();
const projection=elevation.slice(elevation.indexOf('const d2r ='),elevation.indexOf('const sha256 ='));
const sample=new Function(projection+grabFn(elevation,'sampleMosaic')+';return sampleMosaic;')();
const fields=new Map();
for(const [id,folder]of [['berlin','osm'],['taroko','venue_roads']]) {
  const directory=join(source,'test/fixtures',folder,'elevation');
  const fixture=loadElevationFixture(id,directory);
  assert.ok(fixture);assert.equal(validateElevationFixture(fixture,{dir:directory}).ok,true);
  const tiles=fixture.source.tiles.map(tile=>({...tile,image:decode(readFileSync(join(directory,tile.path)))}));
  const xs=tiles.map(tile=>tile.x),ys=tiles.map(tile=>tile.y);
  const bounds={z:fixture.source.zoom,tx0:Math.min(...xs),ty0:Math.min(...ys),
    cols:Math.max(...xs)-Math.min(...xs)+1,rows:Math.max(...ys)-Math.min(...ys)+1};
  fields.set(id,{bounds,mosaic:makeMosaic(tiles,bounds)});
}
const words=values=>Buffer.from(values.buffer,values.byteOffset,values.byteLength);
const context={battleRect:d.battleRect,mapSourceCenter:layers.mapSourceCenter};

test('selected layouts retain their own original frames and omit unselected coverage',()=>{
  const bundles=selectWorldBundles(maps,Object.keys(d.ENV.seasons),
    ['--bundle=berlin_1_spring','--bundle=berlin_1_autumn','--bundle=berlin_swap_2_summer']);
  for(const id of ['berlin','berlin_swap']) {
    const map=[...bundles.values()].find(bundle=>bundle.map.id===id).map;
    const frames=worldElevationFrames(map,bundles,context);
    assert.deepEqual(frames.map(frame=>frame.size),[id==='berlin'?1:2]);
    assert.deepEqual(frames[0].rect,d.battleRect(map.variants[String(frames[0].size)].config));
    assert.notDeepEqual(frames[0].rect,d.battleRect(map.variants['5'].config));
  }
  assert.deepEqual(worldElevationFrames(maps.find(map=>map.id==='taroko'),bundles,context),[]);
});

test('every source sample coordinate and Float32 word matches the original terrain loop across team sizes and assignments',()=>{
  const bundles=selectWorldBundles(maps,Object.keys(d.ENV.seasons),['berlin','taroko']);
  const selected=[...new Map([...bundles.values()].map(bundle=>[bundle.map.id,bundle.map])).values()];
  let checked=0;
  for(const map of selected)for(const frame of worldElevationFrames(map,bundles,context)) {
    const {mosaic,bounds}=fields.get(map.source_id||map.id);
    const expectedQueries=[],actualQueries=[];
    const expected=original(frame.config,d.TERRAIN.GRID_N,d.battleRect,layers.mapSourceCenter,d.xzToLL,
      (lat,lng)=>{expectedQueries.push(lat,lng);return sample(mosaic,bounds,lat,lng);});
    const actual=captureWorldElevation(frame,d.TERRAIN.GRID_N,d.xzToLL,
      (lat,lng)=>{actualQueries.push(lat,lng);return sample(mosaic,bounds,lat,lng);});
    assert.equal(expected.elevationComplete,true);
    assert.deepEqual(words(actual),words(expected.rawElev),map.id+'/'+frame.size);
    assert.deepEqual(words(new Float64Array(actualQueries)),words(new Float64Array(expectedQueries)),map.id+'/'+frame.size);
    checked++;
  }
  assert.equal(checked,20);
});

test('original elevation layer center survives mixed presentation frames; invalid captures reject',()=>{
  const config=structuredClone(maps.find(map=>map.id==='berlin').variants['1'].config);
  const originalCenter=structuredClone(config.center);
  config.center.lat+=.01;
  config.gen={mode:'mixed',version:layers.MIXED_SOURCE_VERSION,layers:{elevation:{center:originalCenter}}};
  const map={id:'mixed-probe',variants:{'1':{config}}};
  const [frame]=worldElevationFrames(map,new Map([['probe',{map,size:1}]]),context);
  assert.deepEqual(frame.center,originalCenter);
  const sampleElev=(lat,lng)=>lat-lng;
  assert.deepEqual(words(captureWorldElevation(frame,d.TERRAIN.GRID_N,d.xzToLL,sampleElev)),
    words(original(config,d.TERRAIN.GRID_N,d.battleRect,layers.mapSourceCenter,d.xzToLL,sampleElev).rawElev));
  for(const value of [NaN,Infinity,-Infinity])
    assert.throws(()=>captureWorldElevation(frame,2,d.xzToLL,()=>value),/Incomplete/);
  for(const grid of [0,1,2.5,NaN])assert.throws(()=>captureWorldElevation(frame,grid,d.xzToLL,sampleElev),/grid/);
});

test('Float32 sampling preserves source signed zeros, subnormal rounding and row order',()=>{
  const config=maps.find(map=>map.id==='berlin').variants['1'].config;
  const frame={rect:d.battleRect(config),center:layers.mapSourceCenter(config,'elevation')};
  const samples=[-0,0,2**-149,2**-150,-(2**-150),1/3,-1/3,16777217,-16777217];
  let expectedIndex=0,actualIndex=0;
  const expected=original(config,3,d.battleRect,layers.mapSourceCenter,d.xzToLL,()=>samples[expectedIndex++]);
  const actual=captureWorldElevation(frame,3,d.xzToLL,()=>samples[actualIndex++]);
  assert.deepEqual(words(actual),words(expected.rawElev));
  assert.equal(actualIndex,9);assert.equal(expectedIndex,9);
  assert.ok(Object.is(actual[0],-0));assert.ok(Object.is(actual[4],-0));
});
