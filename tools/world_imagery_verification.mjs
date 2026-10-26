import {readFile,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {constants as bufferConstants} from 'node:buffer';
import {join} from 'node:path';
import {inflateRawSync,gunzipSync} from 'node:zlib';
import {bufferDigest} from './world_source_writer.mjs';
import {stringifySourceJson} from './source_json.mjs';

const hash=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const integer=value=>Number.isSafeInteger(value)&&value>=0;
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);

// Storage and captured-pixel consistency only; no native geographic projection,
// environment classification, rendered world or delivery parity is established.
export async function verifyWorldImagery(index,directory,resourceDirectory='res://data/world_imagery') {
  if(!record(index)||index.formatVersion!==1||index.scope!=='original-low-resolution-imagery-input-only'
    ||index.complete!==true||!integer(index.width)||!integer(index.height)||!index.width||!index.height
    ||index.width%256||index.height%256||!integer(index.z)||index.z<10||index.z>15
    ||!integer(index.tx0)||!integer(index.ty0)||!Array.isArray(index.tiles)||!Array.isArray(index.probes))
    throw new Error('Invalid original imagery manifest');
  const size=index.width*index.height*4;
  if(!integer(size)||size>bufferConstants.MAX_LENGTH)throw new Error('Invalid original imagery extent');
  const {fingerprint,...content}=index;
  if(!hash(fingerprint)||digest(stringifySourceJson(content))!==fingerprint)throw new Error('Original imagery fingerprint mismatch');
  const stored=async(spec,kind)=>{
    const suffix=kind==='tile'?'.tile':'.rgba8.gz';
    if(!record(spec)||!hash(spec.sha256)||!hash(spec.rawSha256)||!integer(spec.bytes)||!spec.bytes
      ||!integer(spec.rawBytes)||!spec.rawBytes||spec.rawBytes>bufferConstants.MAX_LENGTH
      ||spec.encoding!==(kind==='tile'?'source-image':'rgba8-gzip')
      ||spec.path!==resourceDirectory+'/blobs/'+spec.sha256+suffix)
      throw new Error('Invalid original imagery blob declaration');
    const path=join(directory,'blobs',spec.sha256+suffix);
    if((await stat(path)).size!==spec.bytes||await bufferDigest(path)!==spec.sha256)
      throw new Error('Original imagery stored bytes changed');
    return path;
  };
  const raster=async spec=>{
    if(spec?.rawBytes!==size)throw new Error('Original imagery raster shape mismatch');
    const bytes=await readFile(await stored(spec,'rgba8'));
    if(bytes.length<18||bytes[0]!==31||bytes[1]!==139||bytes[2]!==8||bytes[3]!==0)
      throw new Error('Unsupported original imagery GZIP header');
    const inflated=inflateRawSync(bytes.subarray(10),{info:true,maxOutputLength:size});
    if(inflated.engine.bytesWritten!==bytes.length-18)throw new Error('Trailing original imagery GZIP input');
    // The standard wrapper validates CRC/ISIZE after exact member extent checks.
    const raw=gunzipSync(bytes,{maxOutputLength:size});
    if(raw.length!==size||digest(raw)!==spec.rawSha256)throw new Error('Original imagery decoded bytes changed');
    return raw;
  };
  const raw=await raster(index.raw);await raster(index.display);
  const columns=index.width/256,rows=index.height/256;
  if(index.tiles.length!==columns*rows||index.tx0+columns>2**index.z||index.ty0+rows>2**index.z)
    throw new Error('Incomplete original imagery tile coverage');
  const expected=new Set();
  for(let row=0;row<rows;row++)for(let column=0;column<columns;column++)
    expected.add('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/'+index.z+'/'+(index.ty0+row)+'/'+(index.tx0+column));
  for(const tile of index.tiles) {
    if(!expected.delete(tile.url)||!tile.contentType?.startsWith('image/'))throw new Error('Invalid original imagery tile identity');
    await stored(tile,'tile');
    if(tile.sha256!==tile.rawSha256||tile.bytes!==tile.rawBytes)throw new Error('Original tile extent/hash mismatch');
  }
  const scalar=hex=>{
    if(typeof hex!=='string'||!/^[a-f0-9]{16}$/.test(hex))throw new Error('Invalid original imagery scalar word');
    return Buffer.from(hex,'hex').readDoubleLE();
  };
  const names=['latitude','longitude','rotation','cosine','sine','latitudeCosine','realScale','earthRadius','pi'];
  if(!record(index.constantsLE)||Object.keys(index.constantsLE).length!==names.length)throw new Error('Missing original imagery projection constants');
  for(const name of names)if(!Number.isFinite(scalar(index.constantsLE[name])))throw new Error('Invalid original projection constant');
  for(const probe of index.probes) {
    if(!record(probe)||probe.pointLE?.length!==2||probe.projectionLE?.length!==4)throw new Error('Invalid original imagery probe');
    probe.pointLE.forEach(scalar);
    const [,,px,py]=probe.projectionLE.map(scalar),outside=px<0||py<0||px>=index.width||py>=index.height;
    if([px,py].some(value=>Number.isFinite(value)&&!Number.isInteger(value)))throw new Error('Nonintegral original imagery pixel');
    const offset=(py*index.width+px)*4;
    const values=[raw[offset],raw[offset+1],raw[offset+2]].map(value=>value===undefined?'undefined':value);
    const ordinary=outside?{kind:'null'}:{kind:'rgb',values};
    const validOnly=outside||!raw[offset+3]?{kind:'null'}:{kind:'rgb',values};
    if(stringifySourceJson(probe.ordinary)!==stringifySourceJson(ordinary)
      ||stringifySourceJson(probe.validOnly)!==stringifySourceJson(validOnly))
      throw new Error('Original imagery probe no longer matches raw classification pixels');
  }
  return {tiles:index.tiles.length,pixels:index.width*index.height,probes:index.probes.length};
}
