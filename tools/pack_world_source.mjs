import {copyFile,mkdir} from 'node:fs/promises';
import {constants} from 'node:fs';
import {resolve,dirname,basename,join,relative,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readWorldHeader,readLegacyWorldMeshes} from './world_source.mjs';
import {WorldSourceWriter} from './world_source_writer.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url)),path=resolve(process.argv[2]||'');
const within=relative(join(root,'data/worlds'),path);
if(!within||isAbsolute(within)||within.startsWith('..')||!path.endsWith('.json'))throw new Error('Select an existing source world JSON inside data/worlds');
console.log('WORLD_SOURCE_PACK_HEADER '+basename(path));
const header=await readWorldHeader(path);
if(header.worldSourceVersion!==undefined)throw new Error('Source world is already packed or has an unsupported version');
const writer=new WorldSourceWriter(dirname(path));
for await(const mesh of readLegacyWorldMeshes(path)) {
  await writer.append(mesh);
  if(writer.count%4096===0)console.log('WORLD_SOURCE_PACK_MESHES '+writer.count);
}
const storage=await writer.finish();
const backup=join(root,'artifacts/source-world-backups');
await mkdir(backup,{recursive:true});
await copyFile(path,join(backup,basename(path)+'.original-'+Date.now()),constants.COPYFILE_EXCL);
await writeFixtureJson(path,{...header,...storage});
console.log('WORLD_SOURCE_PACK_PASS '+JSON.stringify({file:basename(path),meshes:storage.meshCount,chunks:storage.meshChunks.length}));
