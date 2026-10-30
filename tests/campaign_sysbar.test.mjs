import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const read=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('original system bar styling and raster provenance',async()=>{
  const capture=await read('tests/fixtures/campaign_sysbar.json');
  const data=await read('data/campaign_sysbar.json');
  const provenance=await read('data/provenance.json');
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,hash] of Object.entries(capture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(capture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.deepEqual(capture.rules,{top:[5/255,7/255,10/255,.95],bottom:[5/255,7/255,10/255,0],
    border:[122/255,158/255,178/255,.18],borderWidth:1});
  assert.deepEqual(capture.cases.map(row=>row.size),[[16,24],[101,50],[320,75]]);
  for(const row of capture.cases){
    const png=Buffer.from(row.png,'base64');
    assert.ok(png.length>=24&&png.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')));
    assert.equal(png.toString('ascii',12,16),'IHDR');
    assert.equal(png.readUInt32BE(16),row.size[0]);
    assert.equal(png.readUInt32BE(20),row.size[1]);
  }
});
