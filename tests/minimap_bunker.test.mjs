import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const json=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('bunker memory fixture retains original snapshot source and persistence cases',async()=>{
  const fixture=await json('tests/fixtures/minimap_bunker.json');
  const provenance=await json('data/provenance.json');
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.equal(fixture.frames.length,7);
  assert.deepEqual(fixture.frames.map(frame=>frame.records.length),[0,2,4,4,6,7,7]);
  assert.deepEqual(fixture.frames[1].records.map(record=>record.key),['0,0','1,1']);
  assert.deepEqual(fixture.frames[2].records.map(record=>record.key),['0,0','1,1','-1,-1','19,29']);
  assert.deepEqual(fixture.frames[3].records,fixture.frames[2].records);
  assert.deepEqual(fixture.frames[6].records,fixture.frames[5].records);
  assert.equal(fixture.frames[4].records[0].side,'MILI');
  assert.equal(fixture.frames[5].records[0].side,'STEEL');
  for(const frame of fixture.frames){
    assert.equal(frame.markers.length,frame.records.length);
    for(const marker of frame.markers)assert.deepEqual(marker.rect.slice(2),[5,5]);
  }
});
