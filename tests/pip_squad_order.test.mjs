import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_squad_order.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original PiP selection sorts published squad indices stably',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.equal(capture.defaultSquadCount,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.name),['reversed','equal','low_power','reduced_resolution',
    'dead_first','self_and_other_peer','missing_indices']);
  assert.deepEqual(capture.programs.map(row=>row.selected),[[2,3],[7,8],[12],[32],[23,22],[44,43],[51,52]]);
});
