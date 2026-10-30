import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_status_persistence.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original campaign status classes persist across finished playback',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.scenario),['no_warning','warning_persisted','warning_expired','warning_ready','warning_during_exit']);
  for(const program of capture.programs){
    const chapter=program.records.find(row=>row.action==='chapter');
    assert.equal(chapter.ready,true);
    assert.equal(chapter.warning,['warning_persisted','warning_ready','warning_during_exit'].includes(program.scenario));
    const late=program.records.find(row=>row.action==='late_warning');
    if(late)assert.equal(late.warning,true);
    assert.equal(program.records.at(-1).warning,chapter.warning);
  }
});
