import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_touch_bundle.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic touch handlers retain Chromium contact event ordering',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  const byName=Object.fromEntries(capture.programs.map(program=>[program.name,program]));
  assert.equal(capture.programs.length,6);
  const together=byName['same-target-batched-release'].frames.at(-1);
  assert.deepEqual(together.events.filter(event=>event.type==='touchend').map(event=>event.changed),[[1],[2]]);
  assert.deepEqual(together.skips,['doubletap']);
  const different=byName['button-and-root-batched'].frames.at(-1);
  assert.deepEqual(different.events.filter(event=>event.type==='touchend').map(event=>event.target),['root','prologueFinishBtn']);
  assert.deepEqual(different.skips,[]);
  assert.deepEqual(byName['separate-release-outside-window'].frames.at(-1).skips,[]);
  const canceled=byName['batched-cancel'].frames.at(-1);
  assert.deepEqual(canceled.events.filter(event=>event.type==='touchcancel').map(event=>event.changed),[[1,2]]);
  assert.equal(canceled.lastTap,0);
  assert.deepEqual(canceled.skips,[]);
});
