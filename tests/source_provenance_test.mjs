import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {captureGenerator,verifyGenerator,captureSourceFiles,verifySourceFiles,captureWorkspaceInputs,verifyWorkspaceInputs} from '../tools/source_provenance.mjs';

async function folder(){await mkdir('artifacts/source-identity-tests',{recursive:true});return mkdtemp(resolve('artifacts/source-identity-tests/case-'));}
const hash=value=>createHash('sha256').update(value).digest('hex');

test('generator identity covers nested producers, serializers and pinned package inputs',async()=>{
  const root=await folder();await mkdir(join(root,'tools/nested'),{recursive:true});
  for(const [name,value]of [['capture.mjs','export const v=1;'],['nested/serialize.mjs','export const v=2;'],['pnpm-lock.yaml','lockfileVersion: 9']])
    await writeFile(join(root,'tools',name),value);
  const producer=await captureGenerator(root);
  assert.deepEqual(Object.keys(producer.inputs).sort(),['tools/capture.mjs','tools/nested/serialize.mjs','tools/pnpm-lock.yaml']);
  await verifyGenerator(root,producer);
  await writeFile(join(root,'tools/nested/serialize.mjs'),'export const v=3;');
  await assert.rejects(verifyGenerator(root,producer),/generator revision is stale/);
});

test('source inputs changed during capture cannot be relabeled with their later hash',async()=>{
  const root=await folder();await writeFile(join(root,'data.js'),'before');
  const captured=await captureSourceFiles(root);
  await writeFile(join(root,'data.js'),'after');
  await assert.rejects(verifySourceFiles(root,{'data.js':hash('before')},captured),/Original source changed/);
  await assert.rejects(verifySourceFiles(root,{'data.js':hash('after')},captured),/Original source changed/);
});

test('a source dependency discovered only after capture started is rejected',async()=>{
  const root=await folder(),captured=await captureSourceFiles(root);
  await writeFile(join(root,'late.js'),'late');
  await assert.rejects(verifySourceFiles(root,{'late.js':hash('late')},captured),/Original source changed/);
});

test('native world metadata inputs cannot drift or gain a new variant during capture',async()=>{
  const root=await folder();await mkdir(join(root,'data/worlds'),{recursive:true});
  await writeFile(join(root,'data/worlds/first.json'),'{"source":1}');
  const expected=await captureWorkspaceInputs(root);await verifyWorkspaceInputs(root,expected);
  await writeFile(join(root,'data/worlds/first.json'),'{"source":2}');
  await assert.rejects(verifyWorkspaceInputs(root,expected),/Native world inputs changed/);
  await writeFile(join(root,'data/worlds/first.json'),'{"source":1}');
  await writeFile(join(root,'data/worlds/second.json'),'{"source":1}');
  await assert.rejects(verifyWorkspaceInputs(root,expected),/Native world inputs changed/);
});
