import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,readdir,writeFile,rm,stat} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {dirname,join,relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gzipSync,gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {writeFixtureJson} from '../tools/fixture_json.mjs';
import {readWorldHeader,readLegacyWorldMeshes,verifyWorldStorage} from '../tools/world_source.mjs';

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
  assert.deepEqual(await verifyWorldStorage(manifest,directory,resourceRoot),{meshes:3,chunks:1,buffers:2});
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

test('existing mesh chunks are verified and reused without rewriting their publication',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'chunk-reuse-'));
  const capture=async()=>{
    const writer=new WorldSourceWriter(directory,'res://fixture');
    try {await writer.append({name:'retained',positions:[1,2,3]});return await writer.finish();}
    finally {await writer.dispose();}
  };
  const first=await capture();
  const folder=join(directory,'mesh_chunks'),names=await readdir(folder);
  const path=join(folder,names[0]),original=await readFile(path);
  const before=await stat(path);
  assert.deepEqual(await capture(),first);
  const after=await stat(path);
  assert.equal(after.ino,before.ino);
  assert.equal(after.mtimeMs,before.mtimeMs);
  const corrupt=Buffer.from(original);
  corrupt[Math.floor(corrupt.length/2)]^=1;
  await writeFile(path,corrupt);
  await assert.rejects(capture(),/Corrupt source mesh chunk hash/);
  assert.deepEqual(await readFile(path),corrupt);
  await writeFile(path,original.subarray(1));
  await assert.rejects(capture(),/Corrupt source mesh chunk length/);
  assert.deepEqual(await readFile(path),original.subarray(1));
  assert.deepEqual(await readdir(folder),names);
  await writeFile(path,original);
  assert.deepEqual(await capture(),first);
});

for(const published of [false,true])test(`legacy pack failure releases its temporary sidecar and retains published content (prior=${published})`,async()=>{
  const worlds=join(root,'data/worlds');
  await mkdir(worlds,{recursive:true});
  const directory=await mkdtemp(join(worlds,'pack-failure-'));
  try {
    const path=join(directory,'interrupted.json');
    // The first transfer opens/writes a sidecar; the next transfer fails validation.
    const positions=Array.from({length:65537},(_,index)=>index===65536?null:index/7);
    const meshes=published?[{positions:Array.from({length:4097},(_,index)=>index/11)},{positions}]:[{positions}];
    const original=JSON.stringify({source:{identity:'retained'},meshes});
    await writeFile(path,original);
    await assert.rejects(promisify(execFile)(process.execPath,[join(root,'tools/pack_world_source.mjs'),path],
      {cwd:root,timeout:10000}),error=>{
      assert.match(error.stderr,/Unsupported nonnumeric source mesh array/);
      return true;
    });
    assert.equal(await readFile(path,'utf8'),original);
    const buffers=await readdir(join(directory,'buffers'));
    assert.equal(buffers.length,published?1:0);
    if(published) {
      const bytes=await readFile(join(directory,'buffers',buffers[0]));
      assert.equal(buffers[0],digest(bytes)+'.f64.gz');
      assert.deepEqual(gunzipSync(bytes),Buffer.from(new Float64Array(meshes[0].positions).buffer));
    }
    assert.deepEqual(await readdir(join(directory,'mesh_chunks')),[]);
  } finally {
    assert.equal(dirname(directory),worlds);
    await rm(directory,{recursive:true,force:true});
  }
});

for(const compressed of [false,true])test(`completed bundle verification rejects missing, corrupt and inconsistent dependencies (gzip=${compressed})`,async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'verify-'));
  const writer=new WorldSourceWriter(directory,'res://fixture',compressed);
  await writer.begin(0,{name:'ground',positions:{$sourceArray:0},nested:{clone:{$sourceArray:0}}},[128]);
  await writer.part(0,0,Array.from({length:128},(_,index)=>index/7));
  await writer.end(0);
  const manifest=await writer.finish();
  await writer.dispose();
  const verify=world=>verifyWorldStorage(world,directory,'res://fixture');
  assert.deepEqual(await verify(manifest),{meshes:1,chunks:1,buffers:1});
  const chunk=manifest.meshChunks[0],chunkPath=join(directory,'mesh_chunks',chunk.path.split('/').at(-1));
  const packed=await readFile(chunkPath),rows=JSON.parse(gunzipSync(packed));
  const spec=rows[0].positions.$sourceNumericArray;
  assert.equal(spec.encoding,compressed?'float64le-gzip':'float64le');
  const path=join(directory,'buffers',spec.path.split('/').at(-1)),original=await readFile(path);
  await rm(path);
  await assert.rejects(verify(manifest),{code:'ENOENT'});
  const corrupt=Buffer.from(original);corrupt[0]^=1;
  await writeFile(path,corrupt);
  await assert.rejects(verify(manifest),/buffer hash mismatch/);
  await writeFile(path,original.subarray(1));
  await assert.rejects(verify(manifest),/buffer length mismatch/);
  await writeFile(path,original);
  const changedRows=async change=>{
    const changed=structuredClone(rows);
    change(changed);
    const plain=Buffer.from(JSON.stringify(changed)),bytes=gzipSync(plain),sha256=digest(bytes);
    await writeFile(join(directory,'mesh_chunks',sha256+'.json.gz'),bytes);
    return {...manifest,meshChunks:[{...chunk,path:'res://fixture/mesh_chunks/'+sha256+'.json.gz',
      sha256,bytes:bytes.length,plainBytes:plain.length}]};
  };
  for(const [change,error]of [
    [value=>{value[0].positions.$sourceNumericArray.shape=[];},/array declaration/],
    [value=>{value[0].positions.$sourceNumericArray.shape=[0];},/array extent/],
    [value=>{value[0].positions.$sourceNumericArray.shape=[268435456];},/array extent/],
    [value=>{value[0].positions.$sourceNumericArray.path='res://fixture/buffers/../foreign.f64';},/buffer path/],
    [value=>{value[0].positions.$sourceNumericArray.sha256='G'.repeat(64);},/buffer declaration/],
    [value=>{value[0].positions.extra=true;},/array declaration/],
    [value=>{value[0].positions={$sourceArray:0};},/Unfinished source numeric transfer/],
    [value=>{value[0].positions.$sourceNumericArray.shape=[129];},compressed?/decompression length mismatch/:/storage mismatch/],
    [value=>{value[0].positions.$sourceNumericArray.shape=[127];},compressed?/decompression extent exceeded/:/storage mismatch/],
    [value=>{value[0].nested.clone.$sourceNumericArray.shape=[129];},compressed?/Conflicting source numeric array extent/:/storage mismatch/],
    [value=>{value[0].nested.clone.$sourceNumericArray.bytes++;},compressed?/Conflicting source world buffer extent/:/storage mismatch/],
    [value=>{value[0]=null;},/Invalid source world mesh chunk/],
  ])await assert.rejects(verify(await changedRows(change)),error);
  if(compressed) {
    const invalid=Buffer.from('Not a GZIP stream'),sha256=digest(invalid);
    await writeFile(join(directory,'buffers',sha256+'.f64.gz'),invalid);
    const invalidStream=await changedRows(value=>Object.assign(value[0].positions.$sourceNumericArray,
      {sha256,bytes:invalid.length,path:'res://fixture/buffers/'+sha256+'.f64.gz'}));
    await assert.rejects(verify(invalidStream),/Invalid source world GZIP header/);
  }
  await assert.rejects(verify({...manifest,worldSourceVersion:3}),/Unsupported source world mesh manifest/);
  await assert.rejects(verify({...manifest,meshCount:2}),/Incomplete source world mesh manifest/);
  await assert.rejects(verify({...manifest,meshChunks:[{...chunk,start:1}]}),/chunk order/);
  await assert.rejects(verify({...manifest,meshChunks:[{...chunk,plainBytes:chunk.plainBytes-1}]}),/decompression extent exceeded/);
  await assert.rejects(verify({...manifest,meshChunks:[{...chunk,plainBytes:chunk.plainBytes+1}]}),/decompression length mismatch/);
  await rm(chunkPath);
  await assert.rejects(verify(manifest),{code:'ENOENT'});
  await writeFile(chunkPath,Buffer.from(packed).fill(0));
  await assert.rejects(verify(manifest),/buffer hash mismatch/);
  await writeFile(chunkPath,packed);
  assert.deepEqual(await verify(manifest),{meshes:1,chunks:1,buffers:1});
  assert.deepEqual(await readFile(path),original);
  assert.deepEqual(await readFile(chunkPath),packed);
  assert.deepEqual(await verify({worldSourceVersion:2,meshCount:0,meshChunks:[]}),{meshes:0,chunks:0,buffers:0});
});

test('source bundle verifier rejects invalid selections before reading captures',async()=>{
  for(const args of [[],['../berlin_1_spring'],['berlin_1_spring','extra'],['nonexistent_1_spring']]) {
    await assert.rejects(promisify(execFile)(process.execPath,[join(root,'tools/verify_world_source.mjs'),...args],
      {cwd:root,timeout:10000}),error=>{
      assert.match(error.stderr,/Select exactly one original source world bundle|Unknown or conflicting original world bundle/);
      assert.doesNotMatch(error.stderr,/ENOENT/);
      return true;
    });
  }
});

for(const target of ['numeric','chunk'])test(`source GZIP requires a single member with no trailing input (${target})`,async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'gzip-boundary-'));
  const writer=new WorldSourceWriter(directory,'res://fixture');
  await writer.begin(0,{positions:{$sourceArray:0}},[128]);
  await writer.part(0,0,Array.from({length:128},(_,index)=>index/7));
  await writer.end(0);
  const manifest=await writer.finish();await writer.dispose();
  const chunk=manifest.meshChunks[0],packed=await readFile(join(directory,'mesh_chunks',chunk.path.split('/').at(-1)));
  const rows=JSON.parse(gunzipSync(packed)),numeric=rows[0].positions.$sourceNumericArray;
  const original=target==='chunk'?packed:await readFile(join(directory,'buffers',numeric.path.split('/').at(-1)));
  const cases=[['empty-member',Buffer.concat([original,gzipSync(Buffer.alloc(0))])],
    ['zero-padding',Buffer.concat([original,Buffer.alloc(1)])],
    ['window-padding',Buffer.concat([original,Buffer.alloc(65537)])],
    ['garbage',Buffer.concat([original,Buffer.from('tail')])],
    ['nonempty-member',Buffer.concat([original,gzipSync(Buffer.from('extra'))])],
    ['truncated-trailer',original.subarray(0,original.length-1)],
    ['truncated-deflate',Buffer.concat([original.subarray(0,original.length-9),original.subarray(original.length-8)])]];
  for(const [mode,index]of [['crc',original.length-8],['size',original.length-4],['flags',3]]) {
    const bytes=Buffer.from(original);bytes[index]^=1;cases.push([mode,bytes]);
  }
  for(const [mode,bytes]of cases) {
    const sha256=digest(bytes),folder=target==='chunk'?'mesh_chunks':'buffers';
    const suffix=target==='chunk'?'.json.gz':'.f64.gz',path=join(directory,folder,sha256+suffix);
    await writeFile(path,bytes);
    let candidate;
    if(target==='chunk')candidate={...manifest,meshChunks:[{...chunk,path:'res://fixture/mesh_chunks/'+sha256+suffix,sha256,bytes:bytes.length}]};
    else {
      const changed=structuredClone(rows);
      Object.assign(changed[0].positions.$sourceNumericArray,{path:'res://fixture/buffers/'+sha256+suffix,sha256,bytes:bytes.length});
      const plain=Buffer.from(JSON.stringify(changed)),encoded=gzipSync(plain),chunkHash=digest(encoded);
      await writeFile(join(directory,'mesh_chunks',chunkHash+'.json.gz'),encoded);
      candidate={...manifest,meshChunks:[{...chunk,path:'res://fixture/mesh_chunks/'+chunkHash+'.json.gz',sha256:chunkHash,bytes:encoded.length,plainBytes:plain.length}]};
    }
    await assert.rejects(verifyWorldStorage(candidate,directory,'res://fixture'),undefined,target+': '+mode);
    assert.deepEqual(await readFile(path),bytes);
  }
  assert.deepEqual(await verifyWorldStorage(manifest,directory,'res://fixture'),{meshes:1,chunks:1,buffers:1});
});

test('single-member source GZIP retains bounded high-ratio output and multiple input windows',async()=>{
  for(const kind of ['zeros','varied','chunk']) {
    await mkdir(artifacts,{recursive:true});
    const directory=await mkdtemp(join(artifacts,'gzip-window-')),writer=new WorldSourceWriter(directory,'res://fixture');
    if(kind==='chunk')await writer.append({name:'x'.repeat(1048577)});
    else {
      await writer.begin(0,{positions:{$sourceArray:0}},[131073]);
      await writer.part(0,0,Array.from({length:131073},(_,index)=>kind==='zeros'?0:Math.sin(index)*index));
      await writer.end(0);
    }
    const manifest=await writer.finish();await writer.dispose();
    const chunk=manifest.meshChunks[0];
    let overflow;
    if(kind==='chunk') {
      assert.ok(chunk.plainBytes>1048576&&chunk.bytes<65536);
      overflow={...manifest,meshChunks:[{...chunk,plainBytes:1}]};
    } else {
      const rows=JSON.parse(gunzipSync(await readFile(join(directory,'mesh_chunks',chunk.path.split('/').at(-1)))));
      const spec=rows[0].positions.$sourceNumericArray;
      assert.equal(spec.encoding,'float64le-gzip');
      assert.equal(spec.bytes>65536,kind==='varied');
      spec.shape=[1];
      const plain=Buffer.from(JSON.stringify(rows)),bytes=gzipSync(plain),sha256=digest(bytes);
      await writeFile(join(directory,'mesh_chunks',sha256+'.json.gz'),bytes);
      overflow={...manifest,meshChunks:[{...chunk,path:'res://fixture/mesh_chunks/'+sha256+'.json.gz',sha256,bytes:bytes.length,plainBytes:plain.length}]};
    }
    await assert.rejects(verifyWorldStorage(overflow,directory,'res://fixture'),/decompression extent exceeded/);
    assert.deepEqual(await verifyWorldStorage(manifest,directory,'res://fixture'),{meshes:1,chunks:1,buffers:kind==='chunk'?0:1});
  }
});

test('identical numeric and mesh-chunk bytes are published under both storage paths',async()=>{
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'path-cache-'));
  let mesh,packed,numbers;
  for(let length=1;length<128;length++) {
    const candidate={name:'x'.repeat(length),index:length},bytes=gzipSync(Buffer.from(JSON.stringify([candidate])));
    if(bytes.length%8)continue;
    const values=Array.from({length:bytes.length/8},(_,index)=>bytes.readDoubleLE(index*8));
    if(values.some(value=>!Number.isFinite(value)))continue;
    mesh=candidate;packed=bytes;numbers=values;break;
  }
  assert.ok(mesh,'A finite float64 array can retain the same bytes as a valid compressed chunk');
  const writer=new WorldSourceWriter(directory,'res://fixture',false);
  try {
    await writer.begin(0,{payload:{$sourceArray:0}},[numbers.length]);
    await writer.part(0,0,numbers);
    await writer.end(0);
    await writer.finish();
    await writer.append(mesh);
    const manifest=await writer.finish(),sha256=digest(packed);
    assert.equal(manifest.meshChunks[1].sha256,sha256);
    assert.deepEqual(await readFile(join(directory,'buffers',sha256+'.f64')),packed);
    assert.deepEqual(await readFile(join(directory,'mesh_chunks',sha256+'.json.gz')),packed);
    assert.deepEqual(await verifyWorldStorage(manifest,directory,'res://fixture'),{meshes:2,chunks:2,buffers:1});
  } finally {await writer.dispose();}
});
