import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {encodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';
import {verifyWorldStorage} from '../tools/world_source.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-binary-transfer-tests/',import.meta.url));
async function directory(){await mkdir(artifacts,{recursive:true});return mkdtemp(join(artifacts,'run-'));}
const local=(root,resource)=>join(root,resource.slice('res://binary/'.length));
async function mesh(root,manifest){return JSON.parse(gunzipSync(await readFile(local(root,manifest.meshChunks[0].path))))[0];}
async function numeric(root,spec){const bytes=await readFile(local(root,spec.path));return spec.encoding==='float64le-gzip'?gunzipSync(bytes):bytes;}

for(const compressed of [false,true])test('binary and JSON numeric parts publish identical complete worlds (gzip='+compressed+')',async()=>{
  const flat=Array.from({length:98304},(_,index)=>index%3===0?-0:index/7);
  const matrix=Array.from({length:4100},(_,index)=>[flat[index],0,-0]);
  const arrays=[flat,matrix];
  async function capture(binary,typed=false) {
    const root=await directory(),writer=new WorldSourceWriter(root,'res://binary',compressed);let manifest;
    try {
      await writer.begin(0,{name:'source',positions:{$sourceArray:0},matrix:{$sourceArray:1},inline:[-0,0]},arrays.map(array=>array.length));
      for(let index=0;index<arrays.length;index++) {
        const array=typed&&index===0?new Float64Array(arrays[index]):arrays[index],size=index===0?65536:64;
        for(let offset=0;offset<array.length;offset+=size) {
          const values=array.slice(offset,offset+size);
          if(binary)await writer.partEncoded(index,offset,encodeSourceNumericPart(values));
          else await writer.part(index,offset,values);
        }
      }
      await writer.end(0);manifest=await writer.finish();
    } finally {await writer.dispose();}
    assert.deepEqual(await verifyWorldStorage(manifest,root,'res://binary'),{meshes:1,chunks:1,buffers:2});
    return {root,manifest};
  }
  const baseline=await capture(false),binary=await capture(true);
  assert.deepEqual(binary.manifest,baseline.manifest);
  assert.deepEqual(await readFile(local(binary.root,binary.manifest.meshChunks[0].path)),
    await readFile(local(baseline.root,baseline.manifest.meshChunks[0].path)));
  const saved=await mesh(binary.root,binary.manifest);
  assert.deepEqual(await numeric(binary.root,saved.positions.$sourceNumericArray),Buffer.from(new Float64Array(flat).buffer));
  assert.deepEqual(await numeric(binary.root,saved.matrix.$sourceNumericArray),Buffer.from(new Float64Array(matrix.flat()).buffer));
  for(const encoded of [false,true]) {
    const typed=await capture(encoded,true);
    assert.deepEqual(typed.manifest,baseline.manifest);
    assert.deepEqual(await readFile(local(typed.root,typed.manifest.meshChunks[0].path)),
      await readFile(local(baseline.root,baseline.manifest.meshChunks[0].path)));
    const meshRecord=await mesh(typed.root,typed.manifest);
    assert.deepEqual(await numeric(typed.root,meshRecord.positions.$sourceNumericArray),Buffer.from(new Float64Array(flat).buffer));
  }
});

test('rejected binary parts retain admitted numeric state and never publish malformed input',async()=>{
  const root=await directory(),writer=new WorldSourceWriter(root,'res://binary',false);
  try {
    await writer.begin(0,{values:{$sourceArray:0}},[2]);
    await assert.rejects(writer.part(0,0,new Array(2)),/Unsupported nonnumeric source mesh array/);
    const valid=encodeSourceNumericPart([1]);
    await assert.rejects(writer.partEncoded(0,0,{...valid,data:'!'.repeat(valid.data.length)}),/source numeric transfer encoding/);
    assert.equal(writer.pending.parts[0].rows,0);assert.equal(writer.pending.parts[0].handle,null);assert.equal(writer.temporary.size,0);
    await writer.partEncoded(0,0,valid);
    for(const [index,offset,values]of [[0,2,[2]],[1,1,[2]],[0,1,[[2]]],[0,1,[[2,3]]]])
      await assert.rejects(writer.partEncoded(index,offset,encodeSourceNumericPart(values)),/Out-of-order|rank changed|dimensions/);
    assert.equal(writer.pending.parts[0].rows,1);
    await writer.partEncoded(0,1,encodeSourceNumericPart([2]));await writer.end(0);
    const manifest=await writer.finish(),saved=await mesh(root,manifest);
    assert.deepEqual(await numeric(root,saved.values.$sourceNumericArray),Buffer.from(new Float64Array([1,2]).buffer));
    await writer.dispose();await assert.rejects(writer.partEncoded(0,0,valid),/disposed/);
  } finally {await writer.dispose();}
});
