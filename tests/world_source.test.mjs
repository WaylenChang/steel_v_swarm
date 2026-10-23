import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
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
