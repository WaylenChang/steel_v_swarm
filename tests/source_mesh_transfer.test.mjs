import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {sourceMeshTransfer} from '../tools/source_mesh_transfer.mjs';
import {stringifySourceJson} from '../tools/source_json.mjs';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {verifyWorldStorage} from '../tools/world_source.mjs';

const transfer=value=>sourceMeshTransfer(value,stringifySourceJson);
const values=()=>Array.from({length:5000},(_,index)=>index%3===0?-0:index/7);

test('float64 capture buffers retain inline arrays, alias order and exact numeric identity',()=>{
  const numbers=values(),typed=new Float64Array(numbers),small=typed.slice(0,4096);
  const result=transfer({first:typed,copy:numbers,small});
  assert.equal(result.arrays.length,1);assert.equal(result.arrays[0],typed);
  assert.deepEqual(result.header.first,result.header.copy);
  assert.deepEqual(result.header.small,Array.from(small));
  assert.ok(Object.is(result.header.small[0],-0));
  const positive=typed.slice();positive[0]=0;
  assert.equal(transfer({typed,positive}).arrays.length,2);
  assert.deepEqual(typed,new Float64Array(numbers));
});

test('mesh transfer shares only exactly equal captured arrays without mutating source metadata',()=>{
  const numbers=values(),copy=numbers.slice(),mesh={positions:numbers,celGeometry:{positions:copy},inline:[-0,0],name:'source'};
  const {header,arrays}=transfer(mesh);
  assert.equal(arrays.length,1);assert.equal(arrays[0],numbers);
  assert.deepEqual(header.positions,{$sourceArray:0});assert.deepEqual(header.celGeometry.positions,{$sourceArray:0});
  assert.ok(Object.is(header.inline[0],-0));assert.ok(Object.is(header.inline[1],0));
  assert.equal(mesh.positions,numbers);assert.equal(mesh.celGeometry.positions,copy);
  assert.ok(!Object.hasOwn(copy,'$sourceArray'));
});

test('signed zero and a final-word difference retain separate numeric transfers',()=>{
  const numbers=values(),positive=numbers.slice(),last=numbers.slice();positive[0]=0;last[last.length-1]+=1;
  const {header,arrays}=transfer({numbers,positive,last});
  assert.equal(arrays.length,3);
  assert.deepEqual([header.numbers,header.positive,header.last],[{$sourceArray:0},{$sourceArray:1},{$sourceArray:2}]);
});

test('matrix rank, row widths and exact scalar bits remain distinct',()=>{
  const flat=values(),column=flat.map(value=>[value]),copy=column.map(row=>row.slice());
  const wide=flat.map(value=>[value,0]),negative=flat.map(value=>[value,-0]);
  const {header,arrays}=transfer({flat,column,copy,wide,negative});
  assert.equal(arrays.length,4);assert.deepEqual(header.column,header.copy);
  assert.notDeepEqual(header.flat,header.column);assert.notDeepEqual(header.wide,header.negative);
});

test('inline threshold, first-encounter order and per-mesh boundaries remain unchanged',()=>{
  const small=values().slice(0,4096),large=values().slice(0,4097),second=large.map(value=>value+1);
  const result=transfer({small,second,large,copy:large.slice()});
  assert.deepEqual(result.header.small,small);assert.equal(result.arrays.length,2);
  assert.equal(result.arrays[0],second);assert.equal(result.arrays[1],large);
  assert.equal(transfer({copy:large}).arrays.length,1);
});

test('browser-injected transfer uses the same standalone function and rejects reserved storage markers',()=>{
  const injected=new Function('return ('+sourceMeshTransfer.toString()+');')();
  const numbers=values(),mesh={first:numbers,copy:numbers.slice()};
  assert.deepEqual(injected(mesh,stringifySourceJson),transfer(mesh));
  assert.throws(()=>sourceMeshTransfer(mesh),/numeric JSON encoder/);
  for(const key of ['$sourceArray','$sourceNumericArray'])assert.throws(()=>transfer({nested:{[key]:0}}),/Reserved source mesh storage/);
});

test('shared transfer preserves every source word, shape and reference through complete storage publication',async()=>{
  const root=fileURLToPath(new URL('../artifacts/sol/source-mesh-transfer-tests/',import.meta.url));
  await mkdir(root,{recursive:true});const directory=await mkdtemp(join(root,'run-'));
  const numbers=values(),matrix=numbers.map(value=>[value,-0]);
  const meshSource={positions:numbers,copy:numbers.slice(),matrix,duplicate:matrix.map(row=>row.slice())};
  const writer=new WorldSourceWriter(directory,'res://transfer');
  let manifest;
  try {await writer.append(meshSource);manifest=await writer.finish();}
  finally {await writer.dispose();}
  assert.deepEqual(await verifyWorldStorage(manifest,directory,'res://transfer'),{meshes:1,chunks:1,buffers:2});
  const path=resource=>join(directory,resource.slice('res://transfer/'.length));
  const [mesh]=JSON.parse(gunzipSync(await readFile(path(manifest.meshChunks[0].path))));
  assert.deepEqual(mesh.positions,mesh.copy);assert.deepEqual(mesh.matrix,mesh.duplicate);
  for(const [key,expected]of [['positions',numbers],['matrix',matrix.flat()]]) {
    const spec=mesh[key].$sourceNumericArray,stored=await readFile(path(spec.path));
    const bytes=spec.encoding==='float64le-gzip'?gunzipSync(stored):stored;
    assert.deepEqual(bytes,Buffer.from(new Float64Array(expected).buffer));
  }
  // Replay the prior wire contract, which transmitted every large field separately.
  const originalArrays=[];
  const originalHeader=JSON.parse(stringifySourceJson(meshSource,(_key,value)=>{
    if(Array.isArray(value)&&value.length>4096){originalArrays.push(value);return {$sourceArray:originalArrays.length-1};}
    return value;
  }));
  const baselineDirectory=await mkdtemp(join(root,'baseline-'));
  const baseline=new WorldSourceWriter(baselineDirectory,'res://transfer');let originalManifest;
  try {
    await baseline.begin(0,originalHeader,originalArrays.map(array=>array.length));
    for(let index=0;index<originalArrays.length;index++)await baseline.part(index,0,originalArrays[index]);
    await baseline.end(0);originalManifest=await baseline.finish();
  } finally {await baseline.dispose();}
  assert.equal(originalArrays.length,4);assert.deepEqual(manifest,originalManifest);
  assert.deepEqual(await readFile(path(manifest.meshChunks[0].path)),
    await readFile(join(baselineDirectory,originalManifest.meshChunks[0].path.slice('res://transfer/'.length))));
});
