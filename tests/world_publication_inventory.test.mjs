import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {collectWorldInventory} from '../tools/world_publication_inventory.mjs';
import {selectWorldBundles} from '../tools/world_selection.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-inventory-tests/',import.meta.url));
async function fixture() {
  await mkdir(artifacts,{recursive:true});
  const root=await mkdtemp(join(artifacts,'run-')),source=join(root,'source'),native=join(root,'native');
  await mkdir(source);await mkdir(native);
  const selection=selectWorldBundles([{id:'probe',variants:{1:{}}}],['spring','summer']);
  return {source,native,selection};
}
const manifest=season=>({worldSourceVersion:2,source:{identity:{map:'probe',teamSize:1,season}},slabsCaptured:true,meshes:[]});

test('inventory matches exact seasonal identities and never counts legacy filenames as published bundles',async()=>{
  const {source,native,selection}=await fixture();
  const path=join(source,'probe_1_spring.json'),bytes=JSON.stringify(manifest('spring'));
  await writeFile(path,bytes);
  await writeFile(join(native,'probe_1_spring.res'),Buffer.from('RSCCunqualified payload'));
  await writeFile(join(source,'probe_1.json'),JSON.stringify(manifest('spring')));
  await writeFile(join(native,'probe_1.res'),Buffer.from('RSRCunqualified legacy payload'));
  const report=await collectWorldInventory(selection,source,native);
  assert.equal(report.scope,'availability-only');assert.equal(report.required,2);
  assert.deepEqual(report.summary,{source:{manifest:1,missing:1},native:{present:1,missing:1}});
  assert.deepEqual(report.unselected,{source:['probe_1.json'],native:['probe_1.res']});
  assert.deepEqual(report.bundles[0].source.capturedFlags,{slabsCaptured:true});
  assert.equal(await readFile(path,'utf8'),bytes);
});

test('LFS pointers, invalid native headers and malformed source files remain unavailable',async()=>{
  const {source,native,selection}=await fixture();
  const pointer='version https://git-lfs.github.com/spec/v1\noid sha256:'+'a'.repeat(64)+'\nsize 123456\n';
  await writeFile(join(source,'probe_1_spring.json'),pointer);
  await writeFile(join(native,'probe_1_spring.res'),pointer.replaceAll('\n','\r\n'));
  await writeFile(join(source,'probe_1_summer.json'),'{"truncated":');
  await writeFile(join(native,'probe_1_summer.res'),'not a native resource');
  const report=await collectWorldInventory(selection,source,native);
  assert.deepEqual(report.summary,{source:{lfs_pointer:1,invalid_manifest:1},native:{lfs_pointer:1,invalid_header:1}});
  assert.equal(report.bundles[0].source.declaredBytes,123456);
  assert.equal(report.bundles[0].native.oid,'a'.repeat(64));
});

test('a valid JSON file for another season cannot satisfy the selected bundle identity',async()=>{
  const {source,native,selection}=await fixture();
  await writeFile(join(source,'probe_1_spring.json'),JSON.stringify(manifest('summer')));
  await writeFile(join(source,'probe_1_summer.json'),'version https://git-lfs.github.com/spec/v1\ninvalid');
  const report=await collectWorldInventory(selection,source,native);
  assert.deepEqual(report.summary.source,{identity_mismatch:1,invalid_lfs_pointer:1});
  assert.deepEqual(report.summary.native,{missing:2});
});

test('an empty checkout reports missing source/native directories without inventing availability',async()=>{
  const {source,native,selection}=await fixture();
  const report=await collectWorldInventory(selection,join(source,'absent'),join(native,'absent'));
  assert.deepEqual(report.summary,{source:{missing:2},native:{missing:2}});
  assert.deepEqual(report.unselected,{source:[],native:[]});
});
