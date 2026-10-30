import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_status_flash.json'));
const data=JSON.parse(await read('data/campaign_status_flash.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original status flash keeps timing, repeat and visibility semantics',async()=>{
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.mode),['flash','repeat','progress','expire','reopen','completed_repeat']);
  assert.equal(capture.rules.iterations,2);
  assert.equal(capture.programs[3].warning,false);
  assert.equal(capture.programs[4].warning,true);
  for(const program of capture.programs)
    for(const sample of program.states){
      assert.ok(sample.opacity>=capture.rules.peakOpacity-1e-6&&sample.opacity<=capture.rules.normalOpacity+1e-6);
      assert.ok(sample.scale>=capture.rules.normalScale-1e-6&&sample.scale<=capture.rules.peakScale+1e-6);
    }
});
