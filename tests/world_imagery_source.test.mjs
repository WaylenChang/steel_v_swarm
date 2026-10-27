import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {worldImagerySource} from '../tools/world_imagery_source.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const load=name=>import(pathToFileURL(join(source,name)).href);
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
for(const path of ['public/js/terrain.js','public/js/data.js','tools/audit_src.mjs'])
  assert.equal(createHash('sha256').update(await readFile(join(source,path))).digest('hex'),provenance.inputs[path]);
const {readSrc,grabFn,grabBlock,grabConst}=await load('tools/audit_src.mjs');
const d=await load('public/js/data.js');
const terrain=readSrc('public','js','terrain.js'),data=readSrc('public','js','data.js');
const program=worldImagerySource(terrain,data,grabFn,grabBlock,grabConst);
const captured=new Function(program)();
const original=new Function('xzToLL','lon2tx','lat2ty','center','imagery','idata',
  'const iw=imagery.canvas.width,ih=imagery.canvas.height;return (x,z,validOnly=false)=>'
  +grabBlock(terrain,'sampleColor = (x, z, validOnly = false) =>')+';');
const lon2tx=new Function(grabFn(terrain,'lon2tx')+';return lon2tx;')();
const lat2ty=new Function('const d2r=d=>d*Math.PI/180;'+grabFn(terrain,'lat2ty')+';return lat2ty;')();
const words=values=>Buffer.from(new Float64Array(values).buffer);

test('compiled imagery program preserves the complete original sampler and projector arithmetic',()=>{
  const pixels=Uint8ClampedArray.from({length:8*8*4},(_,index)=>(index*17)%256);
  for(const center of [{lat:0,lng:0,rot:0},{lat:52.52,lng:13.4,rot:.7},{lat:-33.86,lng:151.2,rot:-1.25}]) {
    const zoom=14,imagery={canvas:{width:8,height:8},z:zoom,tx0:Math.floor(lon2tx(center.lng,zoom)),ty0:Math.floor(lat2ty(center.lat,zoom))};
    const expected=original(d.xzToLL,lon2tx,lat2ty,center,imagery,pixels),actual=captured.sampler(center,imagery,pixels);
    for(const x of [-100000,-1,-0,0,.0001,1,100000,NaN,Infinity])for(const z of [-100000,-1,-0,0,.0001,1,100000,NaN]) {
      for(const valid of [false,true])assert.deepEqual(actual(x,z,valid),expected(x,z,valid));
      const [lat,lng,px,py]=captured.project(center,imagery,x,z),ll=d.xzToLL(x,z,center);
      assert.deepEqual(words([lat,lng]),words(ll));
      assert.ok(Object.is(px,Math.round((lon2tx(ll[1],zoom)-imagery.tx0)*256)));
      assert.ok(Object.is(py,Math.round((lat2ty(ll[0],zoom)-imagery.ty0)*256)));
    }
  }
});

test('validOnly reads the original alpha byte while ordinary sampling preserves hidden RGB',()=>{
  const center={lat:0,lng:0,rot:0},imagery={canvas:{width:256,height:256},z:14,tx0:8192,ty0:8192};
  const pixels=new Uint8ClampedArray(256*256*4);pixels.set([251,37,19,0]);
  const sample=captured.sampler(center,imagery,pixels);
  assert.deepEqual(sample(0,0,false),[251,37,19]);assert.equal(sample(0,0,true),null);
  pixels[3]=1;assert.deepEqual(sample(0,0,true),[251,37,19]);
});

test('changed original source seams reject rather than compiling a replacement sampler',()=>{
  assert.throws(()=>worldImagerySource(terrain.replace('const IMAGERY =','const MISSING ='),data,grabFn,grabBlock,grabConst),/seam missing/);
  assert.throws(()=>worldImagerySource(terrain.replace('if (px < 0 || py < 0 || px >= iw || py >= ih)','if (false)'),data,grabFn,grabBlock,grabConst),/bounds seam missing/);
});

test('isolated original geography preserves every selected frame without executing unrelated module initialization',async()=>{
  const isolated=new Function(worldImagerySource(terrain,data+'\nthrow new Error("Unrelated module initialization");',grabFn,grabBlock,grabConst))();
  const maps=JSON.parse(await readFile(join(root,'data/maps.json'),'utf8'));
  for(const id of ['taroko','berlin']) {
    const map=maps.find(value=>value.id===id);
    for(const variants of [map.variants,map.swapped_variants])for(const variant of Object.values(variants)) {
      assert.deepEqual(isolated.battleRect(variant.config),d.battleRect(variant.config));
      assert.deepEqual(isolated.battleBBox(variant.config),d.battleBBox(variant.config));
    }
  }
});
