import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const json=async path=>JSON.parse(await readFile(join(root,path),'utf8'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('radio grid fixture preserves original CSS, markup and the empty column',async()=>{
  const fixture=await json('tests/fixtures/dialogue_radio_grid.json');
  const provenance=await json('data/provenance.json');
  for(const [path,hash] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(fixture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.equal(fixture.programs.length,48);
  assert.deepEqual([...new Set(fixture.programs.map(p=>p.viewport[0]))],[360,720,721,1440]);
  for(const sample of fixture.programs){
    assert.equal(sample.gap,12);
    assert.equal(sample.avatar,sample.viewport[0]<=720?40:52);
    assert.equal(sample.text[0],sample.avatar+sample.gap);
    assert.equal(sample.text[2],sample.rowWidth-sample.avatar*Number(1+sample.hasRight)-2*sample.gap);
    assert.equal(sample.right===null,!sample.hasRight);
  }
});
