import {test} from 'node:test';
import assert from 'node:assert/strict';
import promises,{mkdir,mkdtemp,readFile,readdir,writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {setImmediate} from 'node:timers/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {WorldImageryStorage} from '../tools/world_imagery_storage.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-imagery-storage-tests/',import.meta.url));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const local=(root,record)=>join(root,record.path.slice('res://imagery/'.length));
async function directory(){await mkdir(artifacts,{recursive:true});return mkdtemp(join(artifacts,'run-'));}
function barrier(){let release;const promise=new Promise(resolve=>release=resolve);return {promise,release};}
async function intercept(name,replacement,body) {
  const original=promises[name];promises[name]=replacement(original);syncBuiltinESMExports();
  try {await body();}finally {promises[name]=original;syncBuiltinESMExports();}
}

test('source tiles and raw RGBA retain exact bytes and immutable admission snapshots',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery');
  const original=Buffer.from([255,17,29,0,0,127,255,1,19,33,48,255]),input=new Uint8Array(original);
  try {
    const pending=storage.publish('rgba8',input);input.fill(0);
    const rgba=await pending,tile=await storage.publish('tile',original);
    assert.deepEqual(gunzipSync(await readFile(local(root,rgba))),original);
    assert.deepEqual(await readFile(local(root,tile)),original);
    assert.equal(rgba.rawSha256,digest(original));assert.equal(rgba.rawBytes,original.length);
    assert.equal(rgba.sha256,digest(await readFile(local(root,rgba))));
    assert.notEqual(tile.path,rgba.path);
    assert.deepEqual(await storage.publish('rgba8',original),rgba);
  } finally {await storage.dispose();}
});

test('concurrent identical source inputs share one owned atomic publication',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery');let opens=0;
  try {
    await intercept('open',original=>async(...args)=>{
      if(String(args[0]).startsWith(join(root,'blobs')))opens++;
      return original(...args);
    },async()=>{
      const rows=await Promise.all(Array.from({length:12},()=>storage.publish('rgba8',new Uint8Array([1,2,3,255]))));
      assert.ok(rows.every(row=>row.path===rows[0].path));assert.equal(opens,1);
      assert.equal((await readdir(join(root,'blobs'))).length,1);
    });
  } finally {await storage.dispose();}
});

for(const corruption of ['length','hash'])test('fresh readers reject existing '+corruption+' corruption without rewriting it',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery'),bytes=Buffer.from([2,4,6,8]);
  const record=await storage.publish('tile',bytes);await storage.dispose();
  const corrupt=corruption==='length'?Buffer.from([1]):Buffer.from([8,6,4,2]);
  await writeFile(local(root,record),corrupt);
  const reader=new WorldImageryStorage(root,'res://imagery');
  try {await assert.rejects(reader.publish('tile',bytes),/Corrupt existing/);assert.deepEqual(await readFile(local(root,record)),corrupt);}
  finally {await reader.dispose();}
});

test('retirement drains late opens, preserves published caches and rejects completed descriptors',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery'),entered=barrier(),release=barrier();
  const foreign=join(root,'blobs','foreign.partial');await storage.ready;await writeFile(foreign,'foreign');
  let handle;
  await intercept('open',original=>async(...args)=>{
    if(String(args[0]).includes('.partial-')){entered.release();await release.promise;handle=await original(...args);return handle;}
    return original(...args);
  },async()=>{
    const operation=storage.publish('tile',new Uint8Array([3,2,1]));operation.catch(()=>{});
    let retirement;
    try {
      await entered.promise;retirement=storage.dispose();assert.equal(storage.dispose(),retirement);
      let done=false;retirement.then(()=>done=true);await setImmediate();assert.equal(done,false);
      await assert.rejects(storage.publish('tile',new Uint8Array([1])),/retired/);
      release.release();await assert.rejects(operation,/retired/);await retirement;
      assert.equal(handle.fd,-1);assert.equal(await readFile(foreign,'utf8'),'foreign');
      const names=await readdir(join(root,'blobs'));
      assert.equal(names.length,2);assert.ok(names.some(name=>name.endsWith('.tile')));
      assert.ok(!names.some(name=>name.includes('.partial-')));
    } finally {release.release();await Promise.allSettled([operation,retirement]);await storage.dispose();}
  });
});

test('rejected exclusive opens never remove foreign temporary bytes',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery');let foreign;
  await intercept('open',original=>async(...args)=>{
    foreign=String(args[0]);const handle=await original(...args);await handle.writeFile('foreign');await handle.close();
    throw Object.assign(new Error('Foreign staging file'),{code:'EEXIST'});
  },async()=>{await assert.rejects(storage.publish('tile',new Uint8Array([1,2])),{code:'EEXIST'});});
  await storage.dispose();assert.equal(await readFile(foreign,'utf8'),'foreign');
});

test('failed owned writes close handles and remove only their incomplete output',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery');let held;
  const retained=await storage.publish('tile',new Uint8Array([9]));
  await intercept('open',original=>async(...args)=>{
    held=await original(...args);held.writeFile=async()=>{throw new Error('Interrupted image write');};return held;
  },async()=>{await assert.rejects(storage.publish('rgba8',new Uint8Array([1,2,3,4])),/Interrupted image write/);});
  await storage.dispose();assert.equal(held.fd,-1);
  assert.deepEqual(await readdir(join(root,'blobs')),[retained.path.split('/').at(-1)]);
});

test('retirement drains directory preparation and rejects unsupported input before any write',async()=>{
  const root=await directory(),entered=barrier(),release=barrier();
  await intercept('mkdir',original=>async(...args)=>{entered.release();await release.promise;return original(...args);},async()=>{
    const storage=new WorldImageryStorage(root,'res://imagery');
    await entered.promise;
    for(const [kind,input]of [['unknown',new Uint8Array([1])],['tile',[]],['rgba8',new Float32Array([1])],['tile',new Uint8Array()]])
      await assert.rejects(storage.publish(kind,input),/Invalid/);
    const pending=storage.publish('tile',new Uint8Array([1]));pending.catch(()=>{});
    const retirement=storage.dispose();let done=false;retirement.then(()=>done=true);
    await setImmediate();assert.equal(done,false);release.release();
    await assert.rejects(pending,/retired/);await retirement;assert.deepEqual(await readdir(join(root,'blobs')),[]);
  });
});

test('close failures still remove only the owned staging file',async()=>{
  const root=await directory(),storage=new WorldImageryStorage(root,'res://imagery');let held;
  await intercept('open',original=>async(...args)=>{
    held=await original(...args);const close=held.close.bind(held);
    held.close=async()=>{await close();throw new Error('Image close failed');};return held;
  },async()=>{await assert.rejects(storage.publish('tile',new Uint8Array([1,2,3])),/Image close failed/);});
  await storage.dispose();assert.equal(held.fd,-1);assert.deepEqual(await readdir(join(root,'blobs')),[]);
});
