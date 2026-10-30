import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_cadence_clock.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original minimap cadence retains fractional-millisecond decisions',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.name),['warm_boundary','fractional_gate','early_warmup','large_epoch']);
  assert.deepEqual(capture.programs[0].frames.map(frame=>frame.due),[true,false,true,false]);
  assert.deepEqual(capture.programs[1].frames.map(frame=>frame.due),[true,true,false,true]);
});
