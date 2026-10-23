import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,writeFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {writeFixtureJson} from '../tools/fixture_json.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/agy/oracle-validation/fixture-json-validation/',import.meta.url));
async function targetFile() {
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'run-'));
  return {directory,path:join(directory,'fixtures.json')};
}

test('streamed fixture bytes match native JSON encoding',async()=>{
  const target=await targetFile();
  const keyed={toJSON(key){return {key,text:'繁體中文 🚀\n"\\\ud800'};}};
  const custom=[];custom.toJSON=key=>['custom',key];
  const fixtures={skip:undefined,fn(){},text:'測試',rows:[keyed,,undefined,NaN,Infinity,-Infinity,-0,custom],
    keyed,custom,typed:new Uint8Array([0,128,255]),date:new Date('2026-10-22T00:00:00Z'),
    vectors:Array.from({length:2000},(_,index)=>({index,values:[index/3,-index/7,.000001]}))};
  const expected=JSON.stringify(fixtures);
  await writeFile(target.path,'old-data');
  await writeFixtureJson(target.path,fixtures);
  assert.equal(await readFile(target.path,'utf8'),expected);
  assert.deepEqual(await readdir(target.directory),['fixtures.json']);
});

test('failed encoding preserves the published fixture file',async()=>{
  const target=await targetFile();
  await writeFile(target.path,'preserved');
  const cyclic={};cyclic.self=cyclic;
  await assert.rejects(writeFixtureJson(target.path,{valid:[1,2],broken:[cyclic]}),/broken/);
  assert.equal(await readFile(target.path,'utf8'),'preserved');
  assert.deepEqual(await readdir(target.directory),['fixtures.json']);
});

test('an oversized nested mesh container splits without changing native JSON bytes',async()=>{
  const target=await targetFile();
  const keyed={toJSON(key){return {key,value:'來源'};}};
  const mesh={name:'ground',positions:[1/3,-0,NaN,Infinity],nested:{rows:[keyed,,undefined]},omitted:undefined};
  const fixtures={meshes:[mesh],tail:[1,2,3]};
  const nativeStringify=JSON.stringify;
  const expected=nativeStringify(fixtures);
  // Exercise the native single-container size failure without allocating 512 MB.
  JSON.stringify=function(value,...arguments_) {
    if(value&&typeof value==='object'&&Object.keys(value).length===1&&Object.values(value)[0]===mesh)
      throw new RangeError('Invalid string length');
    return nativeStringify(value,...arguments_);
  };
  try {await writeFixtureJson(target.path,fixtures);}
  finally {JSON.stringify=nativeStringify;}
  assert.equal(await readFile(target.path,'utf8'),expected);
  assert.deepEqual(await readdir(target.directory),['fixtures.json']);
});
