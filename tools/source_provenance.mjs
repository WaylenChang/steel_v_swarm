import {createReadStream} from 'node:fs';
import {readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve,relative,isAbsolute} from 'node:path';

const excluded=new Set(['.git','.godot','node_modules','.pnpm-store']);

async function files(root,folder='') {
  const result=[];
  for(const entry of (await readdir(join(root,folder),{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name,'en'))) {
    if(excluded.has(entry.name))continue;
    const name=folder?folder+'/'+entry.name:entry.name;
    if(entry.isSymbolicLink())throw new Error('Source identity cannot follow a symbolic link: '+name);
    if(entry.isDirectory())result.push(...await files(root,name));
    else if(entry.isFile())result.push(name);
  }
  return result;
}

async function digest(path) {
  const hash=createHash('sha256');
  for await(const value of createReadStream(path))hash.update(value);
  return hash.digest('hex');
}

function child(root,name) {
  if(typeof name!=='string'||isAbsolute(name)||name.includes('\\'))throw new Error('Invalid source identity path');
  const path=resolve(root,name),local=relative(root,path);
  if(!local||local==='..'||local.startsWith('../')||local.startsWith('..\\')||isAbsolute(local))
    throw new Error('Source identity path leaves its root: '+name);
  return path;
}

// Seal the migration toolset, including serializers and pinned offline packages.
// The broad tool revision deliberately rejects older completed captures after a
// generator change; a focused publication stamps only the sections it executes.
export async function captureGenerator(root) {
  const inputs={};
  for(const name of await files(join(root,'tools')))
    if(name.endsWith('.mjs')||['package.json','package-lock.json','pnpm-lock.yaml'].includes(name))
      inputs['tools/'+name]=await digest(join(root,'tools',name));
  if(!Object.keys(inputs).length)throw new Error('Missing migration generator files');
  return {format:'migration-generator-sha256-v1',node:process.versions.node,inputs};
}

export async function verifyGenerator(root,expected) {
  if(expected?.format!=='migration-generator-sha256-v1'||!expected.inputs)
    throw new Error('Missing source capture generator identity; regenerate the capture');
  const current=await captureGenerator(root);
  if(expected.node!==current.node||Object.keys(expected.inputs).sort().join('\n')!==Object.keys(current.inputs).sort().join('\n'))
    throw new Error('Source capture generator revision is stale');
  for(const [name,hash]of Object.entries(current.inputs))
    if(expected.inputs[name]!==hash)throw new Error('Source capture generator revision is stale: '+name);
}

// Discover before evaluating any original module. The final selected provenance
// inputs must exist in this snapshot and retain the same complete bytes.
export async function captureSourceFiles(root) {
  const inputs={};
  for(const name of await files(root))inputs[name]=await digest(join(root,name));
  return inputs;
}

export async function verifySourceFiles(root,selected,captured) {
  for(const [name,hash]of Object.entries(selected))
    if(captured[name]!==hash||await digest(child(root,name))!==hash)
      throw new Error('Original source changed during reference capture: '+name);
}

export async function captureWorkspaceInputs(root) {
  const inputs={},folder=join(root,'data/worlds');
  let entries;
  try {entries=await readdir(folder,{withFileTypes:true});}
  catch(error){if(error.code==='ENOENT')return inputs;throw error;}
  for(const entry of entries.filter(value=>value.name.endsWith('.json')).sort((a,b)=>a.name.localeCompare(b.name,'en'))) {
    if(!entry.isFile())throw new Error('Native world input is not an ordinary captured file: '+entry.name);
    const name='data/worlds/'+entry.name;inputs[name]=await digest(join(root,name));
  }
  return inputs;
}

export async function verifyWorkspaceInputs(root,expected) {
  if(!expected||typeof expected!=='object'||Array.isArray(expected))throw new Error('Missing source capture workspace input identity');
  const current=await captureWorkspaceInputs(root);
  if(Object.keys(expected).sort().join('\n')!==Object.keys(current).sort().join('\n'))throw new Error('Native world inputs changed during reference capture');
  for(const [name,hash]of Object.entries(current))
    if(expected[name]!==hash)throw new Error('Native world inputs changed during reference capture: '+name);
}
