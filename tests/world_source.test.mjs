import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,readdir,writeFile} from 'node:fs/promises';
import {join,relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {writeFixtureJson} from '../tools/fixture_json.mjs';
import {readWorldHeader,readLegacyWorldMeshes} from '../tools/world_source.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const artifacts=join(root,'artifacts/agy/oracle-validation/world-source-storage');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('legacy world streaming separates only root meshes and preserves record order',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'legacy-'));
  const path=join(directory,'world.json');
  const meshes=Array.from({length:300},(_,id)=>({id,positions:[id/7,-id,0],nested:{meshes:['retained']}}));
  const metadata={source:{identity:{map:'fixture',season:'spring'}},nested:{meshes:[1,2]},decks:[]};
  const text=JSON.stringify({...metadata,meshes});
  await writeFile(path,text);
  assert.deepEqual(await readWorldHeader(path),metadata);
  const actual=[];
  for await(const mesh of readLegacyWorldMeshes(path))actual.push(mesh);
  assert.deepEqual(actual,JSON.parse(text).meshes);
  // Early consumer cancellation must release the parser pipeline without a rejection.
  for await(const mesh of readLegacyWorldMeshes(path)){assert.equal(mesh.id,0);break;}
});

test('truncated legacy worlds fail instead of publishing a partial mesh sequence',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'truncated-'));
  const path=join(directory,'world.json');
  await writeFile(path,'{"source":{},"meshes":[{"id":0},{"id":');
  await assert.rejects(readWorldHeader(path));
  await assert.rejects(async()=>{for await(const mesh of readLegacyWorldMeshes(path))void mesh;});
});

for(const compressed of [false,true])test(`source mesh chunks retain every numeric bit, shape, field and traversal order (gzip=${compressed})`,async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'run-'));
  const resourceRoot='res://'+relative(root,directory).replaceAll('\\','/');
  const positions=Array.from({length:8193},(_,i)=>i===0?-0:(i-4000)/7);
  const instances=Array.from({length:4097},(_,i)=>Array.from({length:16},(_,j)=>i/13-j/17));
  const meshes=[{name:'ground',positions,instances,visible:true,attributes:{position:{values:positions},small:[0,.25,1.5],flags:[true,false]}},{name:'clone',positions,instances,sourceClimb:true},
    {name:'small',positions:[0,1,2],normal:[.1,.2,.3],nested:{flags:[true,false,null]}}];
  const writer=new WorldSourceWriter(directory,resourceRoot,compressed);
  for(const mesh of meshes)await writer.append(mesh);
  const manifest=await writer.finish();
  assert.equal(manifest.meshCount,meshes.length);
  const decoded=[];
  const decode=async value=>{
    if(value===null||typeof value!=='object')return value;
    if(value.$sourceNumericArray) {
      const spec=value.$sourceNumericArray,path=join(directory,spec.path.slice(resourceRoot.length+1));
      const stored=await readFile(path);
      assert.equal(stored.length,spec.bytes);assert.equal(digest(stored),spec.sha256);
      assert.equal(spec.encoding,compressed?'float64le-gzip':'float64le');
      const bytes=compressed?gunzipSync(stored):stored;
      assert.equal(bytes.length,spec.shape.reduce((count,extent)=>count*extent,8));
      if(compressed)assert.ok(stored.length<bytes.length);
      const values=Array.from({length:bytes.length/8},(_,i)=>bytes.readDoubleLE(i*8));
      return spec.shape.length===1?values:Array.from({length:spec.shape[0]},(_,i)=>values.slice(i*spec.shape[1],(i+1)*spec.shape[1]));
    }
    for(const key of Object.keys(value))value[key]=await decode(value[key]);
    return value;
  };
  let encodedRows;
  for(const chunk of manifest.meshChunks) {
    const bytes=await readFile(join(directory,chunk.path.slice(resourceRoot.length+1)));
    assert.equal(digest(bytes),chunk.sha256);
    const plain=gunzipSync(bytes);assert.equal(plain.length,chunk.plainBytes);
    const rows=JSON.parse(plain);assert.equal(rows.length,chunk.count);
    encodedRows=JSON.parse(plain);
    for(const row of rows)decoded.push(await decode(row));
  }
  assert.deepEqual(decoded,meshes);
  assert.deepEqual(encodedRows[0].positions,encodedRows[1].positions);
  assert.deepEqual(encodedRows[0].instances,encodedRows[1].instances);
  await writeFixtureJson(join(directory,'manifest.json'),manifest);
  await writeFixtureJson(join(artifacts,compressed?'native-case.json':'native-raw-case.json'),{resourceRoot,manifest:resourceRoot+'/manifest.json',
    meshCount:meshes.length,checks:['positions','instances'].map(key=>({key,spec:encodedRows[0][key].$sourceNumericArray,
      numericSha256:digest(Buffer.from(new Float64Array(meshes[0][key].flat()).buffer))}))});
});

test('source numeric transfer rejects gaps and unsupported arrays',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'invalid-'));
  const writer=new WorldSourceWriter(directory);
  await writer.begin(0,{positions:{$sourceArray:0}},[2]);
  await assert.rejects(writer.part(0,1,[1]),/Out-of-order/);
  await assert.rejects(writer.part(0,0,[{x:1},{x:2}]),/nonnumeric/);
  await assert.rejects(writer.end(0),/Incomplete/);
});

for(const compressed of [false,true])test(`existing numeric sidecars are verified before reuse (gzip=${compressed})`,async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'reuse-'));
  const mesh={positions:Array.from({length:8193},(_,index)=>index/7)};
  const capture=async()=>{
    const writer=new WorldSourceWriter(directory,'res://fixture',compressed);
    await writer.append(mesh);
    return writer.finish();
  };
  const first=await capture();
  const names=await readdir(join(directory,'buffers'));
  assert.equal(names.length,1);
  const path=join(directory,'buffers',names[0]);
  const original=await readFile(path);
  assert.deepEqual(await capture(),first);
  assert.deepEqual(await readdir(join(directory,'buffers')),names);
  assert.deepEqual(await readFile(path),original);

  const corrupt=Buffer.from(original);
  corrupt[Math.floor(corrupt.length/2)]^=1;
  await writeFile(path,corrupt);
  await assert.rejects(capture(),/Corrupt source buffer hash/);
  assert.deepEqual(await readFile(path),corrupt);
  await writeFile(path,original.subarray(1));
  await assert.rejects(capture(),/Corrupt source buffer length/);
  await writeFile(path,original);
  assert.deepEqual(await capture(),first);
});

test('compression that increases numeric storage retains the original float64 bytes',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'raw-fallback-'));
  const writer=new WorldSourceWriter(directory,'res://fixture');
  await writer.begin(0,{positions:{$sourceArray:0}},[2]);
  await writer.part(0,0,[-0,Number.MIN_VALUE]);
  await writer.end(0);
  const manifest=await writer.finish();
  const chunk=manifest.meshChunks[0];
  const rows=JSON.parse(gunzipSync(await readFile(join(directory,'mesh_chunks',chunk.path.split('/').at(-1)))));
  const spec=rows[0].positions.$sourceNumericArray;
  assert.equal(spec.encoding,'float64le');
  assert.deepEqual(spec.shape,[2]);
  const stored=await readFile(join(directory,'buffers',spec.path.split('/').at(-1)));
  assert.equal(stored.length,spec.bytes);
  assert.equal(digest(stored),spec.sha256);
  assert.ok(Object.is(stored.readDoubleLE(0),-0));
  assert.equal(stored.readDoubleLE(8),Number.MIN_VALUE);
  assert.deepEqual(await readdir(join(directory,'buffers')),[spec.path.split('/').at(-1)]);
});

test('mesh chunk boundaries retain contiguous starts and complete traversal order',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'chunks-'));
  const writer=new WorldSourceWriter(directory,'res://fixture');
  for(let id=0;id<513;id++)await writer.append({id});
  const manifest=await writer.finish();
  assert.equal(manifest.meshCount,513);
  assert.deepEqual(manifest.meshChunks.map(({start,count})=>({start,count})),
    [{start:0,count:256},{start:256,count:256},{start:512,count:1}]);
  const ids=[];
  for(const chunk of manifest.meshChunks) {
    const stored=await readFile(join(directory,'mesh_chunks',chunk.path.split('/').at(-1)));
    assert.equal(stored.length,chunk.bytes);
    assert.equal(digest(stored),chunk.sha256);
    const plain=gunzipSync(stored);
    assert.equal(plain.length,chunk.plainBytes);
    ids.push(...JSON.parse(plain).map(row=>row.id));
  }
  assert.deepEqual(ids,Array.from({length:513},(_,id)=>id));
});

for(const compressed of [false,true])test(`disposing an interrupted capture releases only its owned temporary files (gzip=${compressed})`,async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'dispose-'));
  const published=new WorldSourceWriter(directory,'res://fixture',compressed);
  await published.append({positions:Array.from({length:8193},(_,index)=>index/7)});
  const manifest=await published.finish();
  const names=await readdir(join(directory,'buffers'));
  const bytes=await readFile(join(directory,'buffers',names[0]));
  const interrupted=new WorldSourceWriter(directory,'res://fixture',compressed);
  const other=new WorldSourceWriter(directory,'res://fixture',compressed);
  for(const writer of [interrupted,other]) {
    await writer.begin(0,{positions:{$sourceArray:0}},[4]);
    await writer.part(0,0,[1,2]);
  }
  const own=interrupted.pending.parts[0].temporary;
  const foreign=other.pending.parts[0].temporary;
  assert.notEqual(own,foreign);
  await interrupted.dispose();
  await interrupted.dispose();
  assert.deepEqual((await readdir(join(directory,'buffers'))).sort(),[names[0],foreign.split(/[\\/]/).at(-1)].sort());
  assert.deepEqual(await readFile(join(directory,'buffers',names[0])),bytes);
  await assert.rejects(interrupted.finish(),/disposed/);
  await assert.rejects(interrupted.begin(0,{},[]),/disposed/);
  await assert.rejects(interrupted.part(0,2,[3,4]),/disposed/);
  await assert.rejects(interrupted.end(0),/disposed/);
  await other.part(0,2,[3,4]);
  await other.end(0);
  await other.finish();
  await other.dispose();
  await published.dispose();
  assert.equal(manifest.meshCount,1);
  assert.ok((await readdir(join(directory,'buffers'))).every(name=>!name.includes('.partial')));
});

test('failed sidecar verification can be disposed without altering the rejected output',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'dispose-rejected-'));
  const mesh={positions:Array.from({length:8193},(_,index)=>index/7)};
  const first=new WorldSourceWriter(directory,'res://fixture');
  await first.append(mesh);
  await first.finish();
  const names=await readdir(join(directory,'buffers'));
  const path=join(directory,'buffers',names[0]);
  const corrupt=Buffer.from(await readFile(path));
  corrupt[10]^=1;
  await writeFile(path,corrupt);
  const rejected=new WorldSourceWriter(directory,'res://fixture');
  await assert.rejects(rejected.append(mesh),/Corrupt source buffer hash/);
  await rejected.dispose();
  assert.deepEqual(await readdir(join(directory,'buffers')),names);
  assert.deepEqual(await readFile(path),corrupt);
});

test('a failed exclusive gzip open never makes the existing file disposal-owned',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'dispose-exclusive-'));
  const writer=new WorldSourceWriter(directory,'res://fixture');
  await writer.begin(0,{positions:{$sourceArray:0}},[2]);
  await writer.part(0,0,[1,2]);
  const foreign=writer.pending.parts[0].temporary+'.gz';
  const sentinel=Buffer.from('Owned by another capture');
  await writeFile(foreign,sentinel,{flag:'wx'});
  await assert.rejects(writer.end(0),{code:'EEXIST'});
  await writer.dispose();
  assert.deepEqual(await readFile(foreign),sentinel);
  assert.deepEqual(await readdir(join(directory,'buffers')),[foreign.split(/[\\/]/).at(-1)]);
});
