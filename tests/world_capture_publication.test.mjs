import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,readdir,writeFile,unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {publishWorldCapture} from '../tools/world_capture_publication.mjs';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {gunzipSync} from 'node:zlib';
import {writeFileSync} from 'node:fs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-capture-publication-tests/',import.meta.url));
const digest=value=>createHash('sha256').update(value).digest('hex');
async function fixture() {
  await mkdir(artifacts,{recursive:true});
  const root=await mkdtemp(join(artifacts,'run-')),sourceDirectory=join(root,'source');
  await mkdir(join(sourceDirectory,'public'),{recursive:true});
  await writeFile(join(sourceDirectory,'public/input.js'),'original source');
  await writeFile(join(sourceDirectory,'public/asset.bin'),'original image');
  const source={inputs:{'public/input.js':digest('original source')}};
  source.inputFingerprint=digest(JSON.stringify(source));
  source.assets={'public/asset.bin':digest('original image'),'public/missing.bin':null};
  source.fingerprint=digest(JSON.stringify(source));
  const world={worldSourceVersion:2,meshCount:0,meshChunks:[],source,positions:[-0,1/3]},path=join(root,'world.json');
  await writeFile(path,'previous completed manifest');
  await writeFile(join(root,'published-sidecar.bin'),'retained sidecar');
  return {root,sourceDirectory,world,path};
}

test('qualified capture publication preserves signed zero and declared provenance without mutating the capture',async()=>{
  const {sourceDirectory,world,path}=await fixture(),before=structuredClone(world);
  await publishWorldCapture(path,world,sourceDirectory);
  assert.deepEqual(JSON.parse(await readFile(path,'utf8')),world);
  assert.deepEqual(world,before);
  assert.ok(Object.is(JSON.parse(await readFile(path,'utf8')).positions[0],-0));
});

test('input drift after capture admission cannot replace a completed manifest or published sidecars',async()=>{
  for(const mode of ['changed','removed']) {
    const {root,sourceDirectory,world,path}=await fixture();
    if(mode==='changed')await writeFile(join(sourceDirectory,'public/input.js'),'edited during capture');
    else await unlink(join(sourceDirectory,'public/input.js'));
    await assert.rejects(publishWorldCapture(path,world,sourceDirectory),/Original world input changed or is missing/);
    assert.equal(await readFile(path,'utf8'),'previous completed manifest');
    assert.equal(await readFile(join(root,'published-sidecar.bin'),'utf8'),'retained sidecar');
    assert.deepEqual((await readdir(root)).sort(),['published-sidecar.bin','source','world.json']);
  }
});

test('changed, removed and newly available assets cannot publish a new capture or rewrite an existing capture',async()=>{
  for(const mode of ['changed','removed','available']) {
    const {root,sourceDirectory,world,path}=await fixture();
    if(mode==='changed')await writeFile(join(sourceDirectory,'public/asset.bin'),'different image');
    else if(mode==='removed')await unlink(join(sourceDirectory,'public/asset.bin'));
    else await writeFile(join(sourceDirectory,'public/missing.bin'),'new image');
    const fresh=join(root,'new-world.json');
    for(const output of [path,fresh])
      await assert.rejects(publishWorldCapture(output,world,sourceDirectory),/Original world asset changed/);
    assert.equal(await readFile(path,'utf8'),'previous completed manifest');
    await assert.rejects(readFile(fresh),{code:'ENOENT'});
    assert.deepEqual((await readdir(root)).sort(),['published-sidecar.bin','source','world.json']);
  }
});

test('forged capture fingerprints reject before atomic publication starts',async()=>{
  const {sourceDirectory,world,path}=await fixture();
  world.source.inputs['public/input.js']='0'.repeat(64);
  await assert.rejects(publishWorldCapture(path,world,sourceDirectory),/provenance fingerprint mismatch/);
  assert.equal(await readFile(path,'utf8'),'previous completed manifest');
});

test('original input changes during storage validation reject before manifest replacement',async()=>{
  const {sourceDirectory,world,path}=await fixture();
  let edited=false;
  // A metadata read places the external edit inside the storage pass without a timer race.
  Object.defineProperty(world,'meshCount',{enumerable:true,get(){
    if(!edited) {
      edited=true;
      writeFileSync(join(sourceDirectory,'public/input.js'),'edited during storage validation');
    }
    return 0;
  }});
  await assert.rejects(publishWorldCapture(path,world,sourceDirectory),/Original world input changed or is missing/);
  assert.ok(edited);
  assert.equal(await readFile(path,'utf8'),'previous completed manifest');
});

for(const compressed of [false,true]) {
  async function populatedFixture() {
    const current=await fixture(),writer=new WorldSourceWriter(current.root,'res://data/worlds',compressed);
    try {
      await writer.append({name:'source mesh',positions:Array.from({length:8193},(_,i)=>i===0?-0:i/7)});
      Object.assign(current.world,await writer.finish());
    } finally {await writer.dispose();}
    const chunk=join(current.root,'mesh_chunks',current.world.meshChunks[0].sha256+'.json.gz');
    const rows=JSON.parse(gunzipSync(await readFile(chunk)));
    const numeric=join(current.root,rows[0].positions.$sourceNumericArray.path.slice('res://data/worlds/'.length));
    return {...current,chunk,numeric};
  }

  test(`completed source chunks and numeric dependencies qualify before manifest replacement (gzip=${compressed})`,async()=>{
    const {root,sourceDirectory,world,path,chunk,numeric}=await populatedFixture();
    const chunkBytes=await readFile(chunk),numericBytes=await readFile(numeric);
    await publishWorldCapture(path,world,sourceDirectory);
    assert.deepEqual(JSON.parse(await readFile(path,'utf8')),world);
    assert.deepEqual(await readFile(chunk),chunkBytes);
    assert.deepEqual(await readFile(numeric),numericBytes);
    assert.equal(await readFile(join(root,'published-sidecar.bin'),'utf8'),'retained sidecar');
  });

  test(`missing or corrupt source dependencies never replace the completed manifest (gzip=${compressed})`,async()=>{
    for(const mode of ['chunk-missing','chunk-corrupt','numeric-missing','numeric-corrupt','chunk-count']) {
      const {root,sourceDirectory,world,path,chunk,numeric}=await populatedFixture();
      const target=mode.startsWith('numeric')?numeric:chunk;
      if(mode.endsWith('missing'))await unlink(target);
      else if(mode.endsWith('corrupt')) {
        const bytes=await readFile(target);bytes[bytes.length-1]^=1;await writeFile(target,bytes);
      } else world.meshChunks[0].count++;
      const before=(await readdir(root)).sort();
      const stored=mode.endsWith('missing')?null:await readFile(target);
      const fresh=join(root,'new-world.json');
      for(const output of [path,fresh])
        await assert.rejects(publishWorldCapture(output,world,sourceDirectory));
      assert.equal(await readFile(path,'utf8'),'previous completed manifest');
      await assert.rejects(readFile(fresh),{code:'ENOENT'});
      assert.equal(await readFile(join(root,'published-sidecar.bin'),'utf8'),'retained sidecar');
      assert.deepEqual((await readdir(root)).sort(),before);
      if(stored)assert.deepEqual(await readFile(target),stored);
      else await assert.rejects(readFile(target),{code:'ENOENT'});
    }
  });
}
