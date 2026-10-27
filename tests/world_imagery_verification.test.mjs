import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gzipSync} from 'node:zlib';
import {WorldImageryStorage} from '../tools/world_imagery_storage.mjs';
import {verifyWorldImagery} from '../tools/world_imagery_verification.mjs';
import {stringifySourceJson} from '../tools/source_json.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-imagery-verification-tests/',import.meta.url));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const seal=value=>{delete value.fingerprint;value.fingerprint=digest(stringifySourceJson(value));return value;};
const word=value=>{const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);return bytes.toString('hex');};
const local=(root,row)=>join(root,row.path.slice('res://imagery/'.length));
async function fixture() {
  await mkdir(artifacts,{recursive:true});const root=await mkdtemp(join(artifacts,'run-'));
  const storage=new WorldImageryStorage(root,'res://imagery'),pixels=Buffer.alloc(256*256*4,255);
  pixels.set([251,37,19,0]);const display=Buffer.from(pixels);display.set([0,0,0,0]);
  try {
    const tile=await storage.publish('tile',Buffer.from('diagnostic image-entity bytes'));
    const raw=await storage.publish('rgba8',pixels),styled=await storage.publish('rgba8',display);
    const probes=[
      {pointLE:[word(0),word(-0)],projectionLE:[word(0),word(0),word(-0),word(0)],
        ordinary:{kind:'rgb',values:[251,37,19]},validOnly:{kind:'null'}},
      {pointLE:[word(1),word(1)],projectionLE:[word(0),word(0),word(1),word(1)],
        ordinary:{kind:'rgb',values:[255,255,255]},validOnly:{kind:'rgb',values:[255,255,255]}},
      {pointLE:[word(NaN),word(0)],projectionLE:[word(NaN),word(NaN),word(NaN),word(NaN)],
        ordinary:{kind:'rgb',values:['undefined','undefined','undefined']},validOnly:{kind:'null'}},
      {pointLE:[word(1),word(2)],projectionLE:[word(0),word(0),word(256),word(0)],
        ordinary:{kind:'null'},validOnly:{kind:'null'}},
    ];
    const index=seal({formatVersion:1,scope:'original-low-resolution-imagery-input-only',complete:true,
      width:256,height:256,z:14,tx0:8192,ty0:8192,raw,display:styled,
      constantsLE:Object.fromEntries(['latitude','longitude','rotation','cosine','sine','latitudeCosine','realScale','earthRadius','pi'].map(key=>[key,word(1)])),
      probes,tiles:[{...tile,url:'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/14/8192/8192',contentType:'image/jpeg'}]});
    return {root,index};
  } finally {await storage.dispose();}
}
async function replaceRaster(root,index,bytes) {
  const sha256=digest(bytes),path='res://imagery/blobs/'+sha256+'.rgba8.gz';
  await writeFile(local(root,{path}),bytes);index.raw={...index.raw,path,sha256,bytes:bytes.length};seal(index);
}

test('verified imagery retains raw hidden RGB, alpha validity, undefined probes and distinct display bytes',async()=>{
  const {root,index}=await fixture();
  assert.deepEqual(await verifyWorldImagery(index,root,'res://imagery'),{tiles:1,pixels:65536,probes:4});
  assert.notEqual(index.raw.rawSha256,index.display.rawSha256);
});

test('stored and decoded corruption fail without rewriting existing source blobs',async()=>{
  for(const mode of ['stored','raw-hash','raw-shape','crc']) {
    const {root,index}=await fixture(),path=local(root,index.raw),original=await readFile(path);
    if(mode==='stored'){const changed=Buffer.from(original);changed[12]^=1;await writeFile(path,changed);}
    if(mode==='raw-hash'){index.raw.rawSha256='0'.repeat(64);seal(index);}
    if(mode==='raw-shape'){index.raw.rawBytes--;seal(index);}
    if(mode==='crc'){const changed=Buffer.from(original);changed[changed.length-8]^=1;await replaceRaster(root,index,changed);}
    await assert.rejects(verifyWorldImagery(index,root,'res://imagery'));
    if(mode==='stored')assert.notDeepEqual(await readFile(path),original);
    else assert.deepEqual(await readFile(path),original);
  }
});

test('single-member imagery GZIP rejects empty second members, garbage and output beyond the declared raster',async()=>{
  for(const mode of ['member','garbage','expanded']) {
    const {root,index}=await fixture(),original=await readFile(local(root,index.raw));
    const bytes=mode==='member'?Buffer.concat([original,gzipSync(Buffer.alloc(0))])
      :mode==='garbage'?Buffer.concat([original,Buffer.from('tail')]):gzipSync(Buffer.alloc(index.raw.rawBytes+1));
    await replaceRaster(root,index,bytes);
    await assert.rejects(verifyWorldImagery(index,root,'res://imagery'));
  }
});

test('coverage, namespaces, metadata words and raw-pixel probe consistency reject forged declarations',async()=>{
  for(const mode of ['fingerprint','coverage','path','word','fraction','display-probe']) {
    const {root,index}=await fixture();
    if(mode==='fingerprint')index.width=512;
    if(mode==='coverage'){index.tiles[0].url=index.tiles[0].url.replace('/8192/8192','/8192/8193');seal(index);}
    if(mode==='path'){index.raw.path=index.raw.path.replace('/blobs/','/../');seal(index);}
    if(mode==='word'){index.constantsLE.pi='not-a-double';seal(index);}
    if(mode==='fraction'){index.probes[0].projectionLE[2]=word(.25);seal(index);}
    if(mode==='display-probe'){index.probes[0].ordinary.values=[0,0,0];seal(index);}
    await assert.rejects(verifyWorldImagery(index,root,'res://imagery'),undefined,mode);
  }
});
