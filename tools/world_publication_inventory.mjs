import {open,readdir,readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readWorldHeader} from './world_source.mjs';
import {selectWorldBundles} from './world_selection.mjs';

async function presence(path) {
  let file;
  try {file=await open(path);}catch(error){if(error.code==='ENOENT')return {state:'missing'};throw error;}
  try {
    const bytes=Buffer.alloc(256),{bytesRead}=await file.read(bytes),size=(await file.stat()).size;
    const prefix=bytes.subarray(0,bytesRead),text=prefix.toString('utf8');
    if(text.startsWith('version https://git-lfs.github.com/spec/v1')) {
      const oid=/\noid sha256:([a-f0-9]{64})\r?\n/.exec(text)?.[1];
      const declared=/\nsize (\d+)\s*$/.exec(text)?.[1];
      return oid&&declared?{state:'lfs_pointer',oid,declaredBytes:Number(declared)}:{state:'invalid_lfs_pointer'};
    }
    return {state:'present',bytes:size,magic:prefix.subarray(0,4).toString('ascii')};
  } finally {await file.close();}
}

async function files(directory,extension) {
  try {return (await readdir(directory)).filter(name=>name.endsWith(extension)).sort();}
  catch(error){if(error.code==='ENOENT')return [];throw error;}
}

// Availability evidence only. Native reload, storage/provenance and full-world acceptance remain separate gates.
export async function collectWorldInventory(selection,sourceDirectory,nativeDirectory) {
  const bundles=[];
  for(const [bundle,expected]of selection) {
    const path=join(sourceDirectory,bundle+'.json');
    let source=await presence(path);
    if(source.state==='present') {
      delete source.magic;
      try {
        const world=await readWorldHeader(path),identity=world.source?.identity;
        const matches=identity&&Object.keys(identity).length===3&&identity.map===expected.map.id
          &&identity.teamSize===expected.size&&identity.season===expected.season;
        source={...source,state:matches?'manifest':'identity_mismatch',storageVersion:world.worldSourceVersion??null,
          capturedFlags:Object.fromEntries(Object.entries(world).filter(([key,value])=>key.endsWith('Captured')&&typeof value==='boolean'))};
      }catch(error){source={state:'invalid_manifest',reason:error.message};}
    }
    const native=await presence(join(nativeDirectory,bundle+'.res'));
    if(native.state==='present'&&!['RSRC','RSCC'].includes(native.magic))native.state='invalid_header';
    bundles.push({bundle,source,native});
  }
  const names=new Set(selection.keys());
  const unselected={source:(await files(sourceDirectory,'.json')).filter(name=>!names.has(name.slice(0,-5))),
    native:(await files(nativeDirectory,'.res')).filter(name=>!names.has(name.slice(0,-4)))};
  const counts=key=>{
    const result={};
    for(const row of bundles)result[row[key].state]=(result[row[key].state]??0)+1;
    return result;
  };
  return {scope:'availability-only',required:bundles.length,summary:{source:counts('source'),native:counts('native')},unselected,bundles};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const root=fileURLToPath(new URL('..',import.meta.url));
  const read=async name=>JSON.parse(await readFile(join(root,'data',name),'utf8'));
  const [maps,campaign,balance]=await Promise.all([read('maps.json'),read('campaign.json'),read('balance.json')]);
  const args=process.argv.slice(2),summary=args.includes('--summary');
  const selection=selectWorldBundles([...maps,...campaign.maps],Object.keys(balance.constants.ENV.seasons),args.filter(arg=>arg!=='--summary'));
  const report=await collectWorldInventory(selection,join(root,'data/worlds'),join(root,'assets/worlds'));
  console.log(JSON.stringify(summary?{scope:report.scope,required:report.required,summary:report.summary,
    unselected:{source:report.unselected.source.length,native:report.unselected.native.length}}:report));
}
