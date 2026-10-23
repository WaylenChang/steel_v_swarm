import {createReadStream,constants} from 'node:fs';
import {copyFile,lstat,mkdir,readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {dirname,isAbsolute,join,relative,resolve} from 'node:path';
import {pipeline} from 'node:stream/promises';
import json from 'stream-json';
import {publishSourceFile} from './fixture_json.mjs';
import {partitionFixtures,updateFixtureSections} from './fixture_sections.mjs';
import {captureGenerator,verifyGenerator,verifyWorkspaceInputs} from './source_provenance.mjs';

async function digest(path) {
  const hash=createHash('sha256');
  for await(const bytes of createReadStream(path))hash.update(bytes);
  return hash.digest('hex');
}

function childPath(root,name) {
  if(typeof name!=='string'||isAbsolute(name)||name.includes('\\'))throw new Error('Invalid captured path: '+name);
  const path=resolve(root,name),local=relative(root,path);
  if(!local||local==='..'||local.startsWith('../')||local.startsWith('..\\')||isAbsolute(local))
    throw new Error('Captured path leaves its root: '+name);
  return path;
}

async function inventory(root,folder='') {
  const files=[];
  for(const entry of await readdir(join(root,folder),{withFileTypes:true})) {
    const name=folder?folder+'/'+entry.name:entry.name;
    if(entry.isSymbolicLink())throw new Error('Source capture contains a symbolic link: '+name);
    if(entry.isDirectory())files.push(...await inventory(root,name));
    else if(entry.isFile())files.push(name);
    else throw new Error('Source capture contains an unsupported entry: '+name);
  }
  return files;
}

async function fixtureKeys(path) {
  const parser=json.parser({streamKeys:false,streamStrings:false,streamNumbers:false,
    packKeys:true,packStrings:false,packNumbers:false});
  const completion=pipeline(createReadStream(path),parser);
  completion.catch(()=>{});
  const keys=new Set();
  let depth=0,root=false;
  try {
    for await(const token of parser) {
      if(token.name==='startObject'||token.name==='startArray') {
        if(depth===0){if(root||token.name!=='startObject')throw new Error('Invalid source fixture root');root=true;}
        depth++;
      } else if(token.name==='endObject'||token.name==='endArray')depth--;
      else if(token.name==='keyValue'&&depth===1) {
        if(keys.has(token.value))throw new Error('Duplicate captured fixture section: '+token.value);
        keys.add(token.value);
      }
    }
    await completion;
  } finally {parser.destroy();await completion.catch(()=>{});}
  if(!root||depth!==0)throw new Error('Incomplete source fixture document');
  return keys;
}

export async function publishReferenceSections(root,source,capture) {
  const path=join(root,'data/fixtures.json'),marker=join(root,'data/provenance.json');
  const previous=await readFile(path),provenance=await readFile(marker);
  const inputs=JSON.parse(provenance).inputs;
  const producer=await captureGenerator(root);
  const verify=async()=>{
    for(const [name,hash]of Object.entries(inputs))
      if(await digest(childPath(source,name))!==hash)throw new Error('Published source input is stale: '+name);
  };
  await verify();
  const sections=await capture();
  await verify();
  await verifyGenerator(root,producer);
  if(!(await readFile(path)).equals(previous)||!(await readFile(marker)).equals(provenance))
    throw new Error('Source publication changed during focused reference capture');
  await updateFixtureSections(path,sections,{expectedRegistry:previous,projectRoot:root,producer});
  console.log('SOURCE_REFERENCE_SECTIONS '+Object.keys(sections).join(','));
}

export async function publishSourceStage(root,source,stage) {
  root=resolve(root);source=resolve(source);stage=resolve(stage);
  if(stage===root||stage===source)throw new Error('Expected a separate completed source capture directory');
  const manifestPath=childPath(stage,'data/provenance.json');
  const provenance=JSON.parse(await readFile(manifestPath,'utf8'));
  if(provenance.runtime!=='GDScript'||!provenance.inputs||!Object.keys(provenance.inputs).length)
    throw new Error('Missing completed source capture provenance');
  const verifyInputs=async()=>{
    for(const [name,hash]of Object.entries(provenance.inputs)) {
      if(!/^[a-f0-9]{64}$/.test(hash)||await digest(childPath(source,name))!==hash)
        throw new Error('Captured source input is stale: '+name);
    }
  };
  await verifyInputs();
  await verifyGenerator(root,provenance.producer);
  await verifyWorkspaceInputs(root,provenance.workspaceInputs);
  const balance=JSON.parse(await readFile(childPath(stage,'data/balance.json'),'utf8'));
  const maps=JSON.parse(await readFile(childPath(stage,'data/maps.json'),'utf8'));
  if(Object.keys(balance.heroes).length!==provenance.heroes||maps.length!==provenance.qualifiedMaps)
    throw new Error('Captured definition/map counts disagree with provenance');
  const keys=await fixtureKeys(childPath(stage,'data/fixtures.json'));
  const required=new Set(['rng','volumes','shield']);
  for(const file of await readdir(join(root,'tests'))) {
    if(file!=='run.gd'&&!file.endsWith('_suite.gd'))continue;
    const text=await readFile(join(root,'tests',file),'utf8');
    for(const match of text.matchAll(/fixtures\.has\("([^"]+)"\)/g))required.add(match[1]);
    for(const match of text.matchAll(/(?<![/\w])fixtures\.([A-Za-z]\w*)\b(?!\s*\()/g))required.add(match[1]);
  }
  const missing=[...required].filter(key=>!keys.has(key));
  if(missing.length)throw new Error('Completed capture lacks registered fixture sections: '+missing.join(', '));
  const files=(await inventory(stage)).sort();
  for(const name of files)if(name.endsWith('.import'))throw new Error('Captured Godot import descriptor cannot replace native resource metadata: '+name);
  for(const name of files)if(name!=='LICENSE'&&!name.startsWith('data/')&&!name.startsWith('assets/'))
    throw new Error('Unexpected source publication output: '+name);
  const hashes=new Map();
  for(const name of files)hashes.set(name,await digest(childPath(stage,name)));
  // Publish each complete encoded file atomically; the provenance is the last
  // commit marker. Capture, publication and runtime acceptance are serialized.
  const marker='data/provenance.json';
  const ordered=files.filter(name=>name!==marker).concat(marker);
  let changed=0;
  for(const name of ordered) {
    if(name===marker){await verifyInputs();await verifyGenerator(root,provenance.producer);await verifyWorkspaceInputs(root,provenance.workspaceInputs);}
    const from=childPath(stage,name),to=childPath(root,name);
    if(name==='data/fixtures.json') {
      await partitionFixtures(from,to,{projectRoot:root,expectedSha256:hashes.get(name),producer:provenance.producer});
      changed++;
      continue;
    }
    try {
      if((await lstat(to)).isSymbolicLink())throw new Error('Publication target is a symbolic link: '+name);
      if(await digest(to)===hashes.get(name))continue;
    } catch(error) {if(error.code!=='ENOENT')throw error;}
    await mkdir(dirname(to),{recursive:true});
    const temporary=to+'.partial-publish-'+process.pid+'-'+Date.now();
    await copyFile(from,temporary,constants.COPYFILE_EXCL);
    if(await digest(temporary)!==hashes.get(name))throw new Error('Capture changed during publication: '+name);
    await publishSourceFile(temporary,to);
    changed++;
  }
  console.log('SOURCE_STAGE_PUBLISHED '+JSON.stringify({files:files.length,changed,fixtureSections:keys.size,sourceInputs:Object.keys(provenance.inputs).length}));
}
