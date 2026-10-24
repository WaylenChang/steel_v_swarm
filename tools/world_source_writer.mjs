import {mkdir,open,stat,rm} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {endianness} from 'node:os';
import {join} from 'node:path';
import {gzipSync,createGzip} from 'node:zlib';
import {createReadStream,createWriteStream} from 'node:fs';
import {pipeline} from 'node:stream/promises';
import {writeSourceFile,publishSourceFile} from './fixture_json.mjs';

async function bufferDigest(path) {
  const hash=createHash('sha256');
  await pipeline(createReadStream(path),hash);
  return hash.digest('hex');
}

// Offline storage only. Native Godot resources remain the runtime delivery format.
export class WorldSourceWriter {
  constructor(directory,resourceDirectory='res://data/worlds',compressNumeric=true) {
    if(endianness()!=='LE')throw new Error('Source numeric packing requires a little-endian build host');
    this.directory=directory;this.resourceDirectory=resourceDirectory;
    this.compressNumeric=compressNumeric;
    this.disposed=false;this.temporary=new Set();
    this.count=0;this.chunks=[];this.rows=[];this.rowBytes=0;this.pending=null;this.verified=new Set();
    this.ready=Promise.all(['buffers','mesh_chunks'].map(folder=>mkdir(join(directory,folder),{recursive:true})));
  }
  async begin(index,header,lengths) {
    if(this.disposed)throw new Error('Source writer is disposed');
    await this.ready;
    if(this.pending||index!==this.count||!header||typeof header!=='object'||!Array.isArray(lengths)
      ||lengths.some(length=>!Number.isInteger(length)||length<=0))throw new Error('Invalid source mesh boundary');
    this.pending={header,parts:lengths.map(length=>({length,rows:0,width:0,hash:createHash('sha256'),handle:null}))};
  }
  async part(index,offset,values) {
    if(this.disposed)throw new Error('Source writer is disposed');
    const part=this.pending?.parts[index];
    if(!part||!Array.isArray(values)||!values.length||offset!==part.rows||offset+values.length>part.length)
      throw new Error('Out-of-order source numeric part');
    const width=Array.isArray(values[0])?values[0].length:1;
    if(width<=0||(part.width&&width!==part.width))throw new Error('Inconsistent source numeric dimensions');
    const flat=width===1&&!Array.isArray(values[0])?values:values.flat();
    if(flat.length!==values.length*width||flat.some(value=>typeof value!=='number'||!Number.isFinite(value))
      ||(Array.isArray(values[0])&&values.some(row=>!Array.isArray(row)||row.length!==width)))
      throw new Error('Unsupported nonnumeric source mesh array');
    if(!part.handle) {
      part.width=width;part.matrix=Array.isArray(values[0]);
      part.temporary=join(this.directory,'buffers',`capture-${process.pid}-${randomUUID()}-${this.count}-${index}.partial`);
      part.handle=await open(part.temporary,'wx');
      this.temporary.add(part.temporary);
    }
    if(part.matrix!==Array.isArray(values[0]))throw new Error('Source numeric array rank changed');
    const numbers=new Float64Array(flat),bytes=Buffer.from(numbers.buffer,numbers.byteOffset,numbers.byteLength);
    part.hash.update(bytes);
    let written=0;
    while(written<bytes.length) {
      const result=await part.handle.write(bytes,written,bytes.length-written);
      if(!result.bytesWritten)throw new Error('Source numeric write made no progress');
      written+=result.bytesWritten;
    }
    part.rows+=values.length;
  }
  async end(index) {
    if(this.disposed)throw new Error('Source writer is disposed');
    const pending=this.pending;
    if(!pending||index!==this.count||pending.parts.some(part=>part.rows!==part.length))throw new Error('Incomplete source mesh');
    const descriptors=[];
    for(const part of pending.parts) {
      await part.handle.close();
      part.handle=null;
      let sha256=part.hash.digest('hex'),bytes=part.length*part.width*8,extension='.f64',encoding='float64le';
      let candidate=part.temporary;
      if(this.compressNumeric) {
        const compressed=part.temporary+'.gz';
        const output=createWriteStream(compressed,{flags:'wx'});
        output.once('open',()=>this.temporary.add(compressed));
        await pipeline(createReadStream(part.temporary),createGzip(),output);
        const packedBytes=(await stat(compressed)).size;
        if(packedBytes<bytes) {
          candidate=compressed;extension='.f64.gz';encoding='float64le-gzip';
          sha256=await bufferDigest(compressed);bytes=packedBytes;
        } else {await rm(compressed);this.temporary.delete(compressed);}
      }
      const name=sha256+extension,target=join(this.directory,'buffers',name);
      if(await this._exists(target,sha256,bytes))await rm(candidate);
      else {await publishSourceFile(candidate,target);this.verified.add(sha256);}
      this.temporary.delete(candidate);
      if(candidate!==part.temporary){await rm(part.temporary);this.temporary.delete(part.temporary);}
      descriptors.push({$sourceNumericArray:{path:this.resourceDirectory+'/buffers/'+name,sha256,bytes,
        encoding,shape:part.matrix?[part.length,part.width]:[part.length]}});
    }
    const restore=value=>{
      if(value===null||typeof value!=='object')return value;
      if(Object.hasOwn(value,'$sourceArray')) {
        const id=value.$sourceArray;
        if(Object.keys(value).length!==1||!Number.isInteger(id)||id<0||id>=descriptors.length)throw new Error('Invalid source numeric reference');
        return descriptors[id];
      }
      for(const key of Object.keys(value))value[key]=restore(value[key]);
      return value;
    };
    const text=JSON.stringify(restore(pending.header));
    if(this.rows.length&&this.rowBytes+text.length>8*1024*1024)await this._flush();
    this.rows.push(text);this.rowBytes+=text.length;this.count++;this.pending=null;
    if(this.rows.length>=256)await this._flush();
  }
  async append(mesh) {
    const parts=[];
    const header=JSON.parse(JSON.stringify(mesh,(_key,value)=>{
      if(value&&typeof value==='object'&&(Object.hasOwn(value,'$sourceArray')||Object.hasOwn(value,'$sourceNumericArray')))
        throw new Error('Reserved source mesh storage property');
      if(Array.isArray(value)&&value.length>4096){parts.push(value);return {$sourceArray:parts.length-1};}
      return value;
    }));
    await this.begin(this.count,header,parts.map(values=>values.length));
    for(let index=0;index<parts.length;index++) {
      const values=parts[index],size=typeof values[0]==='number'?65536:64;
      for(let offset=0;offset<values.length;offset+=size)await this.part(index,offset,values.slice(offset,offset+size));
    }
    await this.end(this.count);
  }
  async _exists(path,sha256,bytes) {
    if(this.verified.has(sha256))return true;
    try {
      if((await stat(path)).size!==bytes)throw new Error('Corrupt source buffer length: '+path);
      if(await bufferDigest(path)!==sha256)throw new Error('Corrupt source buffer hash: '+path);
      this.verified.add(sha256);return true;
    } catch(error) {if(error.code==='ENOENT')return false;throw error;}
  }
  async _flush() {
    if(!this.rows.length)return;
    const plain=Buffer.from('['+this.rows.join(',')+']'),packed=gzipSync(plain);
    const sha256=createHash('sha256').update(packed).digest('hex'),name=sha256+'.json.gz';
    await writeSourceFile(join(this.directory,'mesh_chunks',name),packed);
    const start=this.chunks.reduce((sum,chunk)=>sum+chunk.count,0);
    this.chunks.push({path:this.resourceDirectory+'/mesh_chunks/'+name,sha256,bytes:packed.length,
      plainBytes:plain.length,start,count:this.rows.length});
    this.rows=[];this.rowBytes=0;
  }
  async finish() {
    if(this.disposed)throw new Error('Source writer is disposed');
    if(this.pending)throw new Error('Unfinished original source mesh');
    await this._flush();
    return {worldSourceVersion:2,meshCount:this.count,meshChunks:this.chunks};
  }
  // The producer must stop sending mesh parts before disposing its writer.
  async dispose() {
    this.disposed=true;
    for(const part of this.pending?.parts??[]) {
      if(part.handle){await part.handle.close();part.handle=null;}
    }
    for(const path of this.temporary) {
      await rm(path,{force:true});
      this.temporary.delete(path);
    }
    this.pending=null;this.rows=[];this.rowBytes=0;
  }
}
