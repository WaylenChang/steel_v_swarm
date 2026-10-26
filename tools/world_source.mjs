import {createReadStream} from 'node:fs';
import {readFile,stat} from 'node:fs/promises';
import {compose} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import json from 'stream-json';
import Ignore from 'stream-json/filters/Ignore.js';
import Pick from 'stream-json/filters/Pick.js';
import StreamValues from 'stream-json/streamers/StreamValues.js';
import StreamArray from 'stream-json/streamers/StreamArray.js';
import {createGunzip} from 'node:zlib';
import {join} from 'node:path';
import {bufferDigest} from './world_source_writer.mjs';

// Structure/reference tools consume completed world metadata, not render meshes.
export async function readWorldHeader(path) {
  // Use the native parser for bounded bundles; reserve token streaming for giant captures.
  if((await stat(path)).size<=128*1024*1024) {
    const result=JSON.parse(await readFile(path,'utf8'));
    if(!result||typeof result!=='object'||Array.isArray(result))throw new Error('Invalid source world root: '+path);
    delete result.meshes;
    return result;
  }
  const stream=compose(createReadStream(path),json.parser({streamValues:false}),Ignore.ignore({filter:'meshes'}),StreamValues.streamValues());
  let result;
  for await(const {value}of stream){
    if(result!==undefined)throw new Error('Multiple source world roots: '+path);
    result=value;
  }
  if(!result||typeof result!=='object'||Array.isArray(result))throw new Error('Invalid source world root: '+path);
  return result;
}

export async function* readLegacyWorldMeshes(path) {
  const stream=StreamArray.streamArray({highWaterMark:1});
  const completion=pipeline(createReadStream(path),json.parser({streamValues:false}),Pick.pick({filter:'meshes'}),stream);
  completion.catch(()=>{});
  let index=0;
  try {
    for await(const row of stream){
      if(row.key!==index++)throw new Error('Out-of-order original world mesh');
      yield row.value;
    }
    await completion;
  } finally {
    stream.destroy();
    await completion.catch(()=>{});
  }
}

// Storage integrity only: this does not qualify scenery, materials or source provenance.
export async function verifyWorldStorage(world,directory,resourceDirectory='res://data/worlds') {
  const integer=value=>Number.isSafeInteger(value)&&value>=0;
  const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
  if(!record(world)||world.worldSourceVersion!==2||!integer(world.meshCount)||!Array.isArray(world.meshChunks))
    throw new Error('Unsupported source world mesh manifest');
  let total=0;
  for(const chunk of world.meshChunks) {
    if(!record(chunk)||chunk.start!==total||!integer(chunk.count)||chunk.count===0
      ||!integer(chunk.plainBytes)||chunk.plainBytes===0||chunk.plainBytes>128*1024*1024)
      throw new Error('Invalid source world chunk order/count/extent');
    total+=chunk.count;
    if(!Number.isSafeInteger(total)||total>world.meshCount)throw new Error('Incomplete source world mesh manifest');
  }
  if(total!==world.meshCount)throw new Error('Incomplete source world mesh manifest');
  const verified=new Map();
  const stored=async(spec,folder,extension)=>{
    if(!record(spec)||typeof spec.sha256!=='string'||!/^[a-f0-9]{64}$/.test(spec.sha256)
      ||!integer(spec.bytes)||spec.bytes===0||spec.bytes>2147483647)
      throw new Error('Invalid source world buffer declaration');
    const name=spec.sha256+extension;
    if(spec.path!==resourceDirectory+'/'+folder+'/'+name)throw new Error('Invalid source world buffer path');
    const path=join(directory,folder,name);
    if(verified.has(path)) {
      if(verified.get(path)!==spec.bytes)throw new Error('Conflicting source world buffer extent');
      return path;
    }
    if((await stat(path)).size!==spec.bytes)throw new Error('Source world buffer length mismatch: '+path);
    if(await bufferDigest(path)!==spec.sha256)throw new Error('Source world buffer hash mismatch: '+path);
    verified.set(path,spec.bytes);
    return path;
  };
  const gzip=async(path,expected,retain)=>{
    let size=0;
    const chunks=[];
    await pipeline(createReadStream(path),createGunzip(),async values=>{
      for await(const bytes of values) {
        size+=bytes.length;
        if(size>expected)throw new Error('Source world decompression extent exceeded: '+path);
        if(retain)chunks.push(bytes);
      }
    });
    if(size!==expected)throw new Error('Source world decompression length mismatch: '+path);
    return retain?Buffer.concat(chunks,size):undefined;
  };
  const numeric=new Map();
  const visit=async value=>{
    if(value===null||typeof value!=='object')return;
    if(Object.hasOwn(value,'$sourceArray'))throw new Error('Unfinished source numeric transfer');
    if(Object.hasOwn(value,'$sourceNumericArray')) {
      const spec=value.$sourceNumericArray;
      if(Object.keys(value).length!==1||!record(spec)||!['float64le','float64le-gzip'].includes(spec.encoding)
        ||!Array.isArray(spec.shape)||![1,2].includes(spec.shape.length))
        throw new Error('Invalid source numeric array declaration');
      let count=1;
      for(const extent of spec.shape) {
        if(!integer(extent)||extent===0||extent>Math.floor(268435455/count))
          throw new Error('Invalid source numeric array extent');
        count*=extent;
      }
      const compressed=spec.encoding==='float64le-gzip',plainBytes=count*8;
      if(!compressed&&spec.bytes!==plainBytes)throw new Error('Source numeric array storage mismatch');
      const path=await stored(spec,'buffers',compressed?'.f64.gz':'.f64');
      if(numeric.has(path)) {
        if(numeric.get(path)!==plainBytes)throw new Error('Conflicting source numeric array extent');
      } else {
        if(compressed)await gzip(path,plainBytes,false);
        numeric.set(path,plainBytes);
      }
      return;
    }
    for(const child of Array.isArray(value)?value:Object.values(value))
      if(child!==null&&typeof child==='object')await visit(child);
  };
  for(const chunk of world.meshChunks) {
    const path=await stored(chunk,'mesh_chunks','.json.gz');
    const rows=JSON.parse((await gzip(path,chunk.plainBytes,true)).toString('utf8'));
    if(!Array.isArray(rows)||rows.length!==chunk.count||rows.some(row=>!record(row)))
      throw new Error('Invalid source world mesh chunk');
    for(const row of rows)await visit(row);
  }
  return {meshes:total,chunks:world.meshChunks.length,buffers:numeric.size};
}
