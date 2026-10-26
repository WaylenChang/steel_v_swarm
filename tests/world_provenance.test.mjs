import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,symlink} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {verifyWorldProvenance} from '../tools/world_provenance.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-provenance-tests/',import.meta.url));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
function seal(inputs,assets={}) {
  const source={identity:{map:'probe',teamSize:1,season:'spring'},generatorSha256:'captured-generator',inputs};
  source.inputFingerprint=digest(JSON.stringify(source));source.assets=assets;
  source.fingerprint=digest(JSON.stringify(source));
  return {source};
}
async function fixture() {
  await mkdir(artifacts,{recursive:true});const root=await mkdtemp(join(artifacts,'run-'));
  await mkdir(join(root,'public/js'),{recursive:true});await mkdir(join(root,'public/img'));
  await writeFile(join(root,'public/js/biomes.js'),'original deck index');
  await writeFile(join(root,'public/img/texture.bin'),Buffer.from([0,255,1,127]));
  const world=seal({'public/js/biomes.js':digest('original deck index')},{'public/img/texture.bin':digest(Buffer.from([0,255,1,127])),'public/img/missing.png':null});
  return {root,world};
}

test('original world provenance verifies exact raw input/asset bytes and preserves declared missing assets',async()=>{
  const {root,world}=await fixture(),before=JSON.stringify(world);
  assert.deepEqual(await verifyWorldProvenance(world,root),{inputs:1,assets:2,missingAssets:1});
  assert.equal(JSON.stringify(world),before);
});
test('a changed deck oracle cannot reuse the capture source fingerprint',async()=>{
  const {root,world}=await fixture(),before=JSON.stringify(world);
  await writeFile(join(root,'public/js/biomes.js'),'different deck index');
  await assert.rejects(verifyWorldProvenance(world,root),/Original world input changed or is missing: public\/js\/biomes.js/);
  assert.equal(JSON.stringify(world),before);
});
test('newly available fallback assets and changed raw images invalidate capture reuse',async()=>{
  const first=await fixture();await writeFile(join(first.root,'public/img/missing.png'),'new source image');
  await assert.rejects(verifyWorldProvenance(first.world,first.root),/Original world asset changed: public\/img\/missing.png/);
  const second=await fixture();await writeFile(join(second.root,'public/img/texture.bin'),Buffer.from([1,255,1,127]));
  await assert.rejects(verifyWorldProvenance(second.world,second.root),/Original world asset changed: public\/img\/texture.bin/);
});
test('missing inputs and malformed or tampered provenance fail before source publication',async()=>{
  const {root,world}=await fixture();
  await assert.rejects(verifyWorldProvenance({},root),/Missing original world provenance/);
  const changed=structuredClone(world);changed.source.inputs['public/js/biomes.js']='0'.repeat(64);
  await assert.rejects(verifyWorldProvenance(changed,root),/provenance fingerprint mismatch/);
  const badInput=structuredClone(world);badInput.source.inputFingerprint='0'.repeat(64);
  const {fingerprint,...complete}=badInput.source;badInput.source.fingerprint=digest(JSON.stringify(complete));
  await assert.rejects(verifyWorldProvenance(badInput,root),/input fingerprint mismatch/);
  await assert.rejects(verifyWorldProvenance(seal({'public/js/absent.js':'0'.repeat(64)}),root),/input changed or is missing/);
});
test('declared paths cannot traverse outside the original source directory or asset namespace',async()=>{
  const {root}=await fixture();
  for(const name of ['../outside.js','public/../outside.js','public\\js\\biomes.js','/absolute.js'])
    await assert.rejects(verifyWorldProvenance(seal({[name]:'0'.repeat(64)}),root),/Invalid original world input path/);
  await assert.rejects(verifyWorldProvenance(seal({'public/js/biomes.js':digest('original deck index')},{'server/private':null}),root),/Invalid original world asset/);
});

test('source directory links cannot redirect declared inputs into a different tree',async()=>{
  const {root}=await fixture(),outside=await mkdtemp(join(artifacts,'outside-'));
  await writeFile(join(outside,'biomes.js'),'foreign deck index');
  await symlink(outside,join(root,'public/linked'),'junction');
  const world=seal({'public/linked/biomes.js':digest('foreign deck index')});
  await assert.rejects(verifyWorldProvenance(world,root),/Original world input link escapes/);
});
