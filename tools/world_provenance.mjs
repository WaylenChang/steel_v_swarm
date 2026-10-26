import {createReadStream} from 'node:fs';
import {realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isAbsolute,relative,resolve} from 'node:path';

const digest=value=>createHash('sha256').update(value).digest('hex');
const hash=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const inside=(root,path)=>{const name=relative(root,path);return !isAbsolute(name)&&name!=='..'&&!name.startsWith('../')&&!name.startsWith('..\\');};

async function fileHash(root,name) {
  if(typeof name!=='string'||name.includes('\\')||isAbsolute(name)||name.split('/').some(part=>!part||part==='.'||part==='..'))
    throw new Error('Invalid original world input path: '+name);
  const path=resolve(root,name);
  if(!inside(root,path))throw new Error('Original world input escapes its source directory: '+name);
  let canonical;
  try {canonical=await realpath(path);}catch(error){if(error.code==='ENOENT')return null;throw error;}
  if(!inside(root,canonical))throw new Error('Original world input link escapes its source directory: '+name);
  const value=createHash('sha256');
  for await(const bytes of createReadStream(canonical))value.update(bytes);
  return value.digest('hex');
}

// Verify captured original inputs/assets, not generator freshness, native content or match parity.
export async function verifyWorldProvenance(world,sourceDirectory) {
  const source=world?.source;
  if(!record(source)||!record(source.inputs)||Object.keys(source.inputs).length===0||!record(source.assets)
    ||!hash(source.inputFingerprint)||!hash(source.fingerprint))throw new Error('Missing original world provenance');
  const {fingerprint,...complete}=source;
  if(digest(JSON.stringify(complete))!==fingerprint)throw new Error('Original world provenance fingerprint mismatch');
  const {assets,inputFingerprint,...initial}=complete;
  if(digest(JSON.stringify(initial))!==inputFingerprint)throw new Error('Original world input fingerprint mismatch');
  const root=await realpath(sourceDirectory);
  let inputs=0,assetCount=0,missingAssets=0;
  for(const [name,expected]of Object.entries(source.inputs)) {
    if(!hash(expected))throw new Error('Invalid original world input hash: '+name);
    if(await fileHash(root,name)!==expected)throw new Error('Original world input changed or is missing: '+name);
    inputs++;
  }
  for(const [name,expected]of Object.entries(assets)) {
    if(!name.startsWith('public/')||(expected!==null&&!hash(expected)))throw new Error('Invalid original world asset: '+name);
    if(await fileHash(root,name)!==expected)throw new Error('Original world asset changed: '+name);
    assetCount++;
    if(expected===null)missingAssets++;
  }
  return {inputs,assets:assetCount,missingAssets};
}
