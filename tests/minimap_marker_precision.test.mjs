import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_marker_precision.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('marker coordinates retain the original draw program and window inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected]of Object.entries(capture.source.inputs)){
    const bytes=await read(path);
    assert.equal(digest(path.endsWith('.mjs')?bytes.toString('utf8').replace(/\r\n?/g,'\n'):bytes),expected,path);
  }
  for(const [path,expected]of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.cases.length,96);
  assert.deepEqual(new Set(capture.cases.map(row=>row.viewer)),new Set(['','STEEL','SWARM']));
  for(const row of capture.cases){
    assert.equal(row.commands.filter(command=>command.shape==='missile').length,2);
    assert.equal(row.commands.filter(command=>command.shape==='polygon').length,row.viewer?1:0);
    assert.ok(row.commands.some(command=>command.shape==='circle'));
    assert.ok(row.commands.some(command=>command.shape==='rect'));
  }
});
