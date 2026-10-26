import {test} from 'node:test';
import assert from 'node:assert/strict';
import promises,{mkdir,mkdtemp,readdir,readFile,writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {setImmediate} from 'node:timers/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {encodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

const artifacts=fileURLToPath(new URL('../artifacts/sol/world-source-retirement-tests/',import.meta.url));
function barrier(){let release;const promise=new Promise(resolve=>{release=resolve;});return {promise,release};}
async function directory(){await mkdir(artifacts,{recursive:true});return mkdtemp(join(artifacts,'run-'));}
async function intercept(name,replacement,body) {
  const original=promises[name];promises[name]=replacement(original);syncBuiltinESMExports();
  try {await body();}finally {promises[name]=original;syncBuiltinESMExports();}
}
function watched(promise){let done=false;promise.then(()=>{done=true;},()=>{done=true;});return ()=>done;}

for(const binary of [false,true])test('retirement drains a late numeric open before releasing its owned temporary file (binary='+binary+')',{timeout:5000},async()=>{
  const root=await directory(),writer=new WorldSourceWriter(root),entered=barrier(),release=barrier(),handles=[];
  await writer.begin(0,{positions:{$sourceArray:0}},[2]);
  const foreign=join(root,'buffers/foreign.partial');await writeFile(foreign,'foreign owner');
  await intercept('open',original=>async(...args)=>{
    if(String(args[0]).startsWith(join(root,'buffers','capture-'))) {
      entered.release();await release.promise;const handle=await original(...args);handles.push(handle);return handle;
    }
    return original(...args);
  },async()=>{
    const operation=binary?writer.partEncoded(0,0,encodeSourceNumericPart([1,2])):writer.part(0,0,[1,2]);operation.catch(()=>{});
    let retirement;
    try {
      await entered.promise;retirement=writer.dispose();const done=watched(retirement);
      await setImmediate();assert.equal(done(),false,'retirement cannot resolve before the admitted open settles');
      assert.equal(writer.disposed,true);release.release();
      await assert.rejects(operation,/disposed/);await retirement;
      assert.equal(writer.pending,null);assert.equal(writer.temporary.size,0);
      assert.deepEqual(await readdir(join(root,'buffers')),['foreign.partial']);
      assert.equal(await readFile(foreign,'utf8'),'foreign owner');
    } finally {
      release.release();await Promise.allSettled([operation,retirement]);
      for(const handle of handles)if(handle.fd>=0)await handle.close();
      await writer.dispose();
    }
  });
});

for(const binary of [false,true])test('concurrent retirement waits for admitted numeric writes and performs one cleanup (binary='+binary+')',{timeout:5000},async()=>{
  const root=await directory(),writer=new WorldSourceWriter(root),entered=barrier(),release=barrier();
  await writer.begin(0,{positions:{$sourceArray:0}},[2]);await writer.part(0,0,[1]);
  const handle=writer.pending.parts[0].handle,original=handle.write.bind(handle);
  handle.write=async(...args)=>{entered.release();await release.promise;return original(...args);};
  const operation=binary?writer.partEncoded(0,1,encodeSourceNumericPart([2])):writer.part(0,1,[2]);operation.catch(()=>{});
  let first,second;
  try {
    await entered.promise;first=writer.dispose();second=writer.dispose();const done=watched(first);
    await setImmediate();assert.equal(done(),false,'retirement cannot close a still-admitted write');
    assert.equal(first,second,'concurrent retirement callers share the same cleanup');
    release.release();await assert.rejects(operation,/disposed/);await Promise.all([first,second]);
    assert.equal(handle.fd,-1);assert.deepEqual(await readdir(join(root,'buffers')),[]);
    await assert.rejects(writer.append({positions:[1]}),/disposed/);
  } finally {
    release.release();await Promise.allSettled([operation,first,second]);
    handle.write=original;if(handle.fd>=0)await handle.close();await writer.dispose();
  }
});

test('retirement drains atomic chunk publication but rejects a cancelled completed manifest',{timeout:5000},async()=>{
  const root=await directory(),writer=new WorldSourceWriter(root),entered=barrier(),release=barrier();
  await writer.append({name:'held',positions:[1,2,3]});
  await intercept('rename',original=>async(...args)=>{
    if(String(args[1]).startsWith(join(root,'mesh_chunks'))) {entered.release();await release.promise;}
    return original(...args);
  },async()=>{
    const operation=writer.finish();operation.catch(()=>{});let retirement;
    try {
      await entered.promise;retirement=writer.dispose();const done=watched(retirement);
      await setImmediate();assert.equal(done(),false,'retirement cannot clear rows while their chunk rename is pending');
      release.release();await assert.rejects(operation,/disposed/);await retirement;
      const names=await readdir(join(root,'mesh_chunks'));
      assert.equal(names.length,1);assert.ok(!names[0].includes('.partial'));
      assert.deepEqual(JSON.parse(gunzipSync(await readFile(join(root,'mesh_chunks',names[0])))),[{name:'held',positions:[1,2,3]}]);
      assert.equal(writer.pending,null);assert.equal(writer.rows.length,0);
      await assert.rejects(writer.finish(),/disposed/);
    } finally {release.release();await Promise.allSettled([operation,retirement]);await writer.dispose();}
  });
});

test('retirement waits for constructor directory work without admitting another mesh',{timeout:5000},async()=>{
  const root=await directory(),entered=barrier(),release=barrier();let writer,retirement;
  const owned=new Set([join(root,'buffers'),join(root,'mesh_chunks')]);
  await intercept('mkdir',original=>async(...args)=>{
    if(owned.has(String(args[0]))){entered.release();await release.promise;}
    return original(...args);
  },async()=>{
    try {
      writer=new WorldSourceWriter(root);await entered.promise;
      retirement=writer.dispose();const done=watched(retirement);
      await setImmediate();assert.equal(done(),false,'constructor I/O cannot outlive completed retirement');
      release.release();await retirement;
      assert.equal(writer.pending,null);assert.equal(writer.rows.length,0);
      await assert.rejects(writer.begin(0,{},[]),/disposed/);
    } finally {release.release();await retirement;await writer?.dispose();}
  });
});

test('failed initialization still drains its sibling directory request',{timeout:5000},async()=>{
  const root=await directory(),entered=barrier(),release=barrier(),completed=barrier();let writer,retirement;
  await intercept('mkdir',original=>async(...args)=>{
    if(String(args[0])===join(root,'buffers'))throw Object.assign(new Error('Controlled source directory failure'),{code:'EACCES'});
    if(String(args[0])===join(root,'mesh_chunks')) {
      entered.release();await release.promise;
      try{return await original(...args);}finally{completed.release();}
    }
    return original(...args);
  },async()=>{
    try {
      writer=new WorldSourceWriter(root);await entered.promise;
      await assert.rejects(writer.finish(),{code:'EACCES'});
      retirement=writer.dispose();const done=watched(retirement);
      await setImmediate();assert.equal(done(),false,'a rejected Promise.all cannot hide another live initialization request');
      release.release();await retirement;
      assert.equal(writer.pending,null);assert.deepEqual(await readdir(join(root,'mesh_chunks')),[]);
      await assert.rejects(writer.ready,{code:'EACCES'});
    } finally {release.release();await completed.promise;await retirement;await writer?.dispose();}
  });
});
