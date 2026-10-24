import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,writeFile,access} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {copySourceTree} from '../tools/source_copy.mjs';

test('authored asset copies preserve native descriptors and exclude source editor caches',async()=>{
  await mkdir('artifacts/source-copy-tests',{recursive:true});
  const root=await mkdtemp(resolve('artifacts/source-copy-tests/case-'));
  const source=join(root,'source'),target=join(root,'target');
  await mkdir(join(source,'nested'),{recursive:true});await mkdir(join(target,'nested'),{recursive:true});
  await writeFile(join(source,'nested/asset.bin'),Buffer.from([0,1,2,255]));
  await writeFile(join(source,'nested/asset.bin.import'),'foreign source path');
  await writeFile(join(source,'nested/cache.bin.import'),'foreign cache');
  await writeFile(join(target,'nested/asset.bin.import'),'native source path');
  const observed=[];await copySourceTree(source,target,{recursive:true,onFile:path=>observed.push(path)});
  assert.deepEqual(await readFile(join(target,'nested/asset.bin')),Buffer.from([0,1,2,255]));
  assert.equal(await readFile(join(target,'nested/asset.bin.import'),'utf8'),'native source path');
  await assert.rejects(access(join(target,'nested/cache.bin.import')),/ENOENT/);
  assert.deepEqual(observed,[join(source,'nested/asset.bin')]);
});
