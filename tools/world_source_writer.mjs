import {mkdir,open,stat,rm} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {endianness} from 'node:os';
import {join} from 'node:path';
import {gzipSync,createGzip} from 'node:zlib';
import {createReadStream,createWriteStream} from 'node:fs';
import {pipeline} from 'node:stream/promises';
import {writeSourceFile,publishSourceFile} from './fixture_json.mjs';
import {stringifySourceJson} from './source_json.mjs';
import {sourceMeshTransfer} from './source_mesh_transfer.mjs';
import {decodeSourceNumericPart} from './source_numeric_transfer.mjs';

export async function bufferDigest(path) {
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
    this.operations=new Set();this.disposal=null;
    this.count=0;this.chunks=[];this.rows=[];this.rowBytes=0;this.pending=null;this.verified=new Set();
    const preparation=['buffers','mesh_chunks'].map(folder=>mkdir(join(directory,folder),{recursive:true}));
    this.ready=Promise.all(preparation);
    this.initialization=Promise.allSettled(preparation);
    // Retirement may precede the first mesh; callers still observe initialization errors through ready/operations.
    this.ready.catch(()=>{});
  }
  _run(action) {
    if(this.disposed)return Promise.reject(new Error('Source writer is disposed'));
    const work=this.ready.then(async()=>{
      if(this.disposed)throw new Error('Source writer is disposed');
      const result=await action();
      if(this.disposed)throw new Error('Source writer is disposed');
      return result;
    });
    this.operations.add(work);
    work.then(()=>this.operations.delete(work),()=>this.operations.delete(work));
    return work;
  }
  begin(index,header,lengths){return this._run(()=>this._begin(index,header,lengths));}
  part(index,offset,values){return this._run(()=>this._part(index,offset,values));}
  partEncoded(index,offset,value){return this._run(()=>this._partEncoded(index,offset,value));}
  end(index){return this._run(()=>this._end(index));}
  append(mesh){return this._run(()=>this._append(mesh));}
  finish(){return this._run(()=>this._finish());}

  async _begin(index,header,lengths) {
    if(this.pending||index!==this.count||!header||typeof header!=='object'||!Array.isArray(lengths)
      ||lengths.some(length=>!Number.isInteger(length)||length<=0))throw new Error('Invalid source mesh boundary');
    this.pending={header,parts:lengths.map(length=>({length,rows:0,width:0,hash:createHash('sha256'),handle:null}))};
  }
  async _part(index,offset,values) {
    const part=this.pending?.parts[index];
    if(!part||(!Array.isArray(values)&&!(values instanceof Float64Array))||!values.length||offset!==part.rows||offset+values.length>part.length)
      throw new Error('Out-of-order source numeric part');
    const width=Array.isArray(values[0])?values[0].length:1;
    if(width<=0)throw new Error('Inconsistent source numeric dimensions');
    const flat=width===1&&!Array.isArray(values[0])?values:values.flat();
    if(flat.length!==values.length*width
      ||(Array.isArray(values[0])&&values.some(row=>!Array.isArray(row)||row.length!==width)))
      throw new Error('Unsupported nonnumeric source mesh array');
    for(let index=0;index<flat.length;index++)
      if(typeof flat[index]!=='number'||!Number.isFinite(flat[index]))throw new Error('Unsupported nonnumeric source mesh array');
    const numbers=new Float64Array(flat),bytes=Buffer.from(numbers.buffer,numbers.byteOffset,numbers.byteLength);
    await this._writePart(index,offset,values.length,width,Array.isArray(values[0]),bytes);
  }
  async _partEncoded(index,offset,value) {
    if(!this.pending?.parts[index]||offset!==this.pending.parts[index].rows)throw new Error('Out-of-order source numeric part');
    const {bytes,rows,width,matrix}=decodeSourceNumericPart(value);
    await this._writePart(index,offset,rows,width,matrix,bytes);
  }
  async _writePart(index,offset,rows,width,matrix,bytes) {
    const part=this.pending?.parts[index];
    if(!part||offset!==part.rows||offset+rows>part.length)throw new Error('Out-of-order source numeric part');
    if(part.width&&width!==part.width)throw new Error('Inconsistent source numeric dimensions');
    if(part.width&&part.matrix!==matrix)throw new Error('Source numeric array rank changed');
    if(!part.handle) {
      part.width=width;part.matrix=matrix;
      part.temporary=join(this.directory,'buffers',`capture-${process.pid}-${randomUUID()}-${this.count}-${index}.partial`);
      part.handle=await open(part.temporary,'wx');
      this.temporary.add(part.temporary);
    }
    part.hash.update(bytes);
    let written=0;
    while(written<bytes.length) {
      const result=await part.handle.write(bytes,written,bytes.length-written);
      if(!result.bytesWritten)throw new Error('Source numeric write made no progress');
      written+=result.bytesWritten;
    }
    part.rows+=rows;
  }
  async _end(index) {
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
      else {await publishSourceFile(candidate,target);this.verified.add(target);}
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
    const text=stringifySourceJson(restore(pending.header));
    if(this.rows.length&&this.rowBytes+text.length>8*1024*1024)await this._flush();
    this.rows.push(text);this.rowBytes+=text.length;this.count++;this.pending=null;
    if(this.rows.length>=256)await this._flush();
  }
  async _append(mesh) {
    const {header,arrays:parts}=sourceMeshTransfer(mesh,stringifySourceJson);
    await this.begin(this.count,header,parts.map(values=>values.length));
    for(let index=0;index<parts.length;index++) {
      const values=parts[index],size=typeof values[0]==='number'?65536:64;
      for(let offset=0;offset<values.length;offset+=size)await this.part(index,offset,values.slice(offset,offset+size));
    }
    await this.end(this.count);
  }
  async _exists(path,sha256,bytes,kind='buffer') {
    if(this.verified.has(path))return true;
    try {
      if((await stat(path)).size!==bytes)throw new Error('Corrupt source '+kind+' length: '+path);
      if(await bufferDigest(path)!==sha256)throw new Error('Corrupt source '+kind+' hash: '+path);
      this.verified.add(path);return true;
    } catch(error) {if(error.code==='ENOENT')return false;throw error;}
  }
  async _flush() {
    if(!this.rows.length)return;
    const plain=Buffer.from('['+this.rows.join(',')+']'),packed=gzipSync(plain);
    const sha256=createHash('sha256').update(packed).digest('hex'),name=sha256+'.json.gz';
    const path=join(this.directory,'mesh_chunks',name);
    if(!await this._exists(path,sha256,packed.length,'mesh chunk')) {
      await writeSourceFile(path,packed);
      this.verified.add(path);
    }
    const start=this.chunks.reduce((sum,chunk)=>sum+chunk.count,0);
    this.chunks.push({path:this.resourceDirectory+'/mesh_chunks/'+name,sha256,bytes:packed.length,
      plainBytes:plain.length,start,count:this.rows.length});
    this.rows=[];this.rowBytes=0;
  }
  async _finish() {
    if(this.pending)throw new Error('Unfinished original source mesh');
    await this._flush();
    return {worldSourceVersion:2,meshCount:this.count,meshChunks:this.chunks};
  }
  // Stop future producer calls first; retirement drains every already-admitted I/O operation.
  dispose() {
    if(this.disposal)return this.disposal;
    this.disposed=true;
    this.disposal=this._dispose();
    return this.disposal;
  }
  async _dispose() {
    await Promise.allSettled([this.initialization,...this.operations]);
    for(const part of this.pending?.parts??[]) {
      if(part.handle){await part.handle.close();part.handle=null;}
    }
    for(const path of this.temporary) {
      await rm(path,{force:true});
      this.temporary.delete(path);
    }
    this.pending=null;this.rows=[];this.rowBytes=0;
    // Completed manifests retain their own chunk array after writer retirement.
    this.chunks=[];this.verified.clear();
  }
}
