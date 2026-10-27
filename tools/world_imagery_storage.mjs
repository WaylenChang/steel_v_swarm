import {mkdir,open,rm,stat} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {gzip} from 'node:zlib';
import {promisify} from 'node:util';
import {bufferDigest} from './world_source_writer.mjs';
import {publishSourceFile} from './fixture_json.mjs';

const compress=promisify(gzip);
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

// Offline source images and decoded RGBA are immutable, independently addressed
// inputs. Browser classification must never read the stylized display pixels.
export class WorldImageryStorage {
  constructor(directory,resourceDirectory='res://data/world_imagery') {
    this.directory=directory;this.resourceDirectory=resourceDirectory;
    this.retired=false;this.operations=new Set();this.pending=new Map();this.retirement=null;
    this.ready=mkdir(join(directory,'blobs'),{recursive:true});
    this.ready.catch(()=>{});
  }

  publish(kind,input) {
    if(this.retired)return Promise.reject(new Error('Source imagery storage is retired'));
    if(!['tile','rgba8'].includes(kind)||!(input instanceof Uint8Array)||!input.byteLength)
      return Promise.reject(new TypeError('Invalid source imagery bytes'));
    const bytes=Buffer.from(input);
    const operation=this.ready.then(async()=>{
      if(this.retired)throw new Error('Source imagery storage is retired');
      const packed=kind==='rgba8'?await compress(bytes):bytes;
      const sha256=digest(packed),name=sha256+(kind==='rgba8'?'.rgba8.gz':'.tile');
      const target=join(this.directory,'blobs',name);
      if(!this.pending.has(target))this.pending.set(target,this._store(target,packed,sha256));
      await this.pending.get(target);
      if(this.retired)throw new Error('Source imagery storage is retired');
      return {path:this.resourceDirectory+'/blobs/'+name,sha256,bytes:packed.length,
        encoding:kind==='rgba8'?'rgba8-gzip':'source-image',rawSha256:digest(bytes),rawBytes:bytes.length};
    });
    this.operations.add(operation);
    operation.then(()=>this.operations.delete(operation),()=>this.operations.delete(operation));
    return operation;
  }

  async _store(target,bytes,sha256) {
    try {
      if((await stat(target)).size!==bytes.length||await bufferDigest(target)!==sha256)
        throw new Error('Corrupt existing source imagery: '+target);
      return;
    } catch(error) {if(error.code!=='ENOENT')throw error;}
    const temporary=target+'.partial-'+process.pid+'-'+randomUUID();
    let handle=null,owned=false;
    try {
      handle=await open(temporary,'wx');owned=true;
      await handle.writeFile(bytes);
      await handle.close();handle=null;
      await publishSourceFile(temporary,target);
    } finally {
      try {if(handle)await handle.close();}
      finally {if(owned)await rm(temporary,{force:true});}
    }
  }

  dispose() {
    if(this.retirement)return this.retirement;
    this.retired=true;
    this.retirement=(async()=>{
      await Promise.allSettled([this.ready,...this.operations]);
      this.pending.clear();
    })();
    return this.retirement;
  }
}
