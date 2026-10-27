import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createWorldMeshTransport} from '../tools/world_mesh_transport.mjs';
import {sourceMeshTransfer} from '../tools/source_mesh_transfer.mjs';
import {stringifySourceJson} from '../tools/source_json.mjs';
import {encodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';
import {verifyWorldStorage} from '../tools/world_source.mjs';

const injected=new Function('return ('+createWorldMeshTransport.toString()+');')();
const artifacts=fileURLToPath(new URL('../artifacts/sol/world-mesh-transport-tests/',import.meta.url));
const local=(root,resource)=>join(root,resource.slice('res://transport/'.length));
const dependencies={split:sourceMeshTransfer,stringify:stringifySourceJson,encode:encodeSourceNumericPart};
async function directory(){await mkdir(artifacts,{recursive:true});return mkdtemp(join(artifacts,'run-'));}

for(const compressed of [false,true])test('mixed inline batches and binary meshes retain complete publication bytes (gzip='+compressed+')',async()=>{
  const records=Array.from({length:263},(_,index)=>({name:'source-'+index,positions:new Float64Array([-0,index/7,0]),
    normals:new Float64Array([0,-0,1]),source:{hdr:1.059999942779541,tiny:Number.MIN_VALUE,text:'{"rawJSON":"-0"}'}}));
  for(const index of [17,255]) {
    records[index].positions=new Float64Array(Array.from({length:98304},(_,word)=>word%3===0?-0:word/7));
    records[index].copy=Array.from(records[index].positions);
  }
  async function publish(batched) {
    const root=await directory(),writer=new WorldSourceWriter(root,'res://transport',compressed);
    const batches=[];let collections=0;
    try {
      if(batched) {
        const transport=injected({...dependencies,collect:()=>collections++,
          sendRows:async(offset,text)=>{
            assert.equal(offset,writer.count);const rows=JSON.parse(text);batches.push(rows.length);
            for(const row of rows)await writer.append(row);
          },
          sendMesh:async(operation,index,offset,text)=>{
            if(operation==='begin'){const {header,lengths}=JSON.parse(text);await writer.begin(index,header,lengths);}
            else if(operation==='array-f64')await writer.partEncoded(index,offset,JSON.parse(text));
            else if(operation==='end')await writer.end(index);
            else assert.fail('Unexpected original mesh operation');
          }});
        for(const record of records){await transport.append(record);transport.collect();}
        assert.equal(await transport.finish(),records.length);
        assert.equal(await transport.finish(),records.length);
        await assert.rejects(transport.append(records[0]),/closed/);
      } else for(const record of records)await writer.append(record);
      const manifest=await writer.finish();
      assert.equal((await verifyWorldStorage(manifest,root,'res://transport')).meshes,records.length);
      return {root,manifest,batches,collections};
    } finally {await writer.dispose();}
  }
  const baseline=await publish(false),batched=await publish(true);
  assert.deepEqual(batched.manifest,baseline.manifest);
  for(let index=0;index<baseline.manifest.meshChunks.length;index++)
    assert.deepEqual(await readFile(local(batched.root,batched.manifest.meshChunks[index].path)),
      await readFile(local(baseline.root,baseline.manifest.meshChunks[index].path)));
  assert.ok(batched.batches.every(count=>count>0&&count<=16));
  assert.ok(batched.batches.length<records.length/2);
  assert.equal(batched.collections,0,'Small transfers must not force collection once per mesh');
});

test('byte budget flushes complete inline rows and collection runs only after retired transfers',async()=>{
  const sent=[];let collections=0;
  const transport=injected({...dependencies,sendRows:async(offset,text)=>sent.push({offset,rows:JSON.parse(text)}),
    sendMesh:()=>assert.fail('Inline source must not acquire numeric parts'),collect:()=>collections++},
    {inlineCount:16,inlineBytes:160,collectionBytes:200});
  for(let index=0;index<4;index++) {
    await transport.append({name:'x'.repeat(100),positions:new Float64Array([-0,index,0])});
    transport.collect();
  }
  assert.equal(await transport.finish(),4);
  assert.deepEqual(sent.map(batch=>batch.offset),[0,1,2,3]);
  assert.ok(sent.every(batch=>batch.rows.length===1));
  assert.equal(collections,4);
  assert.equal(transport.collect(),false);
});

test('inline byte bounds include brackets and commas without dropping the boundary row',async()=>{
  const sent=[],record={positions:[-0,1,2]};
  const rowBytes=stringifySourceJson(record).length*2;
  const inlineBytes=rowBytes*2+4;
  const transport=injected({...dependencies,sendRows:async(offset,text)=>{
    assert.ok(text.length*2<=inlineBytes);sent.push({offset,rows:JSON.parse(text)});
  },sendMesh:()=>assert.fail('Unexpected numeric transfer'),collect:()=>{}},{inlineBytes});
  for(let index=0;index<3;index++)await transport.append(record);
  assert.equal(await transport.finish(),3);
  assert.deepEqual(sent.map(batch=>batch.offset),[0,1,2]);
  assert.ok(sent.every(batch=>batch.rows.length===1&&Object.is(batch.rows[0].positions[0],-0)));
});

test('failed or overlapping send operations cannot publish a completed transfer',async()=>{
  for(const kind of ['inline','binary']) {
    const failure=new Error('source send interrupted');
    const transport=injected({...dependencies,sendRows:async()=>{throw failure;},sendMesh:async()=>{throw failure;},collect:()=>{}},
      {inlineCount:1});
    await assert.rejects(transport.append({positions:kind==='inline'?[-0,0,1]:new Float64Array(5000)}),error=>error===failure);
    await assert.rejects(transport.finish(),/closed/);
    await assert.rejects(transport.append({positions:[1]}),/closed/);
  }
  let release,entered;
  const gate=new Promise(resolve=>release=resolve),started=new Promise(resolve=>entered=resolve);
  const transport=injected({...dependencies,sendRows:async()=>{entered();await gate;},sendMesh:()=>{},collect:()=>{}},{inlineCount:1});
  const pending=transport.append({positions:[-0,0,1]});
  await started;
  assert.equal(transport.collect(),false);
  await assert.rejects(transport.append({positions:[2]}),/Overlapping/);
  release();await assert.rejects(pending,/failed/);
  await assert.rejects(transport.finish(),/closed/);
});
