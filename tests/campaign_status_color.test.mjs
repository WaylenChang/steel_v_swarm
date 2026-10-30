import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_status_color.json'));
const data=JSON.parse(await read('data/campaign_status_color.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original campaign status color and reversal retain browser timings',async()=>{
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.mode),['ready','warning','warning_progress','reverse','same_target','double_reverse']);
  assert.equal(capture.rules.duration,.3);
  assert.deepEqual(capture.programs[1].states[0].child,[255,68,54]);
  assert.equal(capture.programs[2].states[0].child,null);
  assert.ok(capture.programs[3].reverseDuration>0&&capture.programs[3].reverseDuration<300);
  assert.ok(capture.programs[5].repeatedDuration>0&&capture.programs[5].repeatedDuration<300);
});
