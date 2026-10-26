import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {stringifySourceJson,prepareSourceJson} from '../tools/source_json.mjs';
import {writeFixtureJson} from '../tools/fixture_json.mjs';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {verifyWorldStorage} from '../tools/world_source.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/source-json-tests/',import.meta.url));
async function directory(){await mkdir(artifacts,{recursive:true});return mkdtemp(join(artifacts,'run-'));}

test('native source JSON retains signed zero and every finite scalar bit without reserving payload strings or keys',()=>{
  const values=[-0,0,Number.MIN_VALUE,-Number.MIN_VALUE,Number.MAX_VALUE,Math.PI,1/3];
  const source={values,rawJSON:'-0',text:'{"rawJSON":"-0"}',nested:{value:-0}};
  const actual=JSON.parse(stringifySourceJson(source));
  for(let index=0;index<values.length;index++)assert.ok(Object.is(actual.values[index],values[index]));
  assert.ok(Object.is(actual.nested.value,-0));
  assert.equal(actual.rawJSON,source.rawJSON);assert.equal(actual.text,source.text);
});
test('toJSON keys and replacer traversal retain native JSON semantics',()=>{
  const calls=[],source={entry:{toJSON(key){calls.push('toJSON:'+key);return {negative:-0,drop:undefined};}}};
  const actual=JSON.parse(stringifySourceJson(source,function(key,value){calls.push(key);return value;}));
  assert.deepEqual(calls,['','toJSON:entry','entry','negative','drop']);
  assert.ok(Object.is(actual.entry.negative,-0));assert.ok(!Object.hasOwn(actual.entry,'drop'));
  assert.equal(stringifySourceJson([undefined,NaN,Infinity]),'[null,null,null]');
});
test('streaming publication preserves inline signed numbers without mutating captured metadata',async()=>{
  const root=await directory(),path=join(root,'metadata.json');
  const source={unchanged:{name:'borrowed'},values:[-0,0,{normal:-0}],scalar:-0};
  const encoded=prepareSourceJson(source);
  assert.notEqual(encoded,source);assert.equal(encoded.unchanged,source.unchanged);
  assert.notEqual(encoded.values,source.values);assert.ok(Object.is(source.values[0],-0));
  await writeFixtureJson(path,encoded);
  const actual=JSON.parse(await readFile(path,'utf8'));
  assert.ok(Object.is(actual.values[0],-0));assert.ok(Object.is(actual.values[1],0));
  assert.ok(Object.is(actual.values[2].normal,-0));assert.ok(Object.is(actual.scalar,-0));
  assert.equal(prepareSourceJson(source.unchanged),source.unchanged);
});
test('publication adaptation rejects cyclic or non-JSON objects instead of inventing a numeric substitute',()=>{
  const cycle={};cycle.self=cycle;
  assert.throws(()=>prepareSourceJson(cycle),/Circular captured source JSON/);
  assert.throws(()=>prepareSourceJson(new Date()),/plain captured JSON/);
  assert.throws(()=>prepareSourceJson({toJSON(){return -0;}}),/plain captured JSON/);
  const values=prepareSourceJson({value:-0});assert.equal(prepareSourceJson(values),values);
});
test('unavailable native raw-number support rejects source capture explicitly',()=>{
  const original=JSON.rawJSON;
  try {
    JSON.rawJSON=undefined;
    assert.throws(()=>stringifySourceJson({number:-0}),/requires native JSON.rawJSON/);
    assert.throws(()=>prepareSourceJson({number:-0}),/requires native JSON.rawJSON/);
  } finally {JSON.rawJSON=original;}
});
test('browser-shaped JSON transfer retains signed bits through inline chunk and numeric sidecar publication',async()=>{
  const root=await directory(),writer=new WorldSourceWriter(root,'res://probe');
  const numbers=Array.from({length:5000},(_,index)=>index%3===0?-0:index/7);
  const source={positions:numbers,normal:[-0,0,1],nested:{matrix:[1,-0,0,-0]}};
  const transferred=JSON.parse(stringifySourceJson(source));
  await writer.append(transferred);const manifest=await writer.finish();await writer.dispose();
  assert.deepEqual(await verifyWorldStorage(manifest,root,'res://probe'),{meshes:1,chunks:1,buffers:1});
  const chunk=JSON.parse(gunzipSync(await readFile(join(root,manifest.meshChunks[0].path.slice('res://probe/'.length)))).toString('utf8'))[0];
  assert.ok(Object.is(chunk.normal[0],-0));assert.ok(Object.is(chunk.normal[1],0));
  assert.ok(Object.is(chunk.nested.matrix[1],-0));
  const spec=chunk.positions.$sourceNumericArray;
  const saved=await readFile(join(root,spec.path.slice('res://probe/'.length)));
  const bytes=spec.encoding==='float64le-gzip'?gunzipSync(saved):saved;
  assert.deepEqual(bytes,Buffer.from(new Float64Array(numbers).buffer));
});
