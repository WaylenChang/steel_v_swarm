import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_chapter_status.json'));
const buffer=JSON.parse(await read('data/campaign_buffer.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original prologue buffers while chapters start with ready status',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  const [prologue,chapter]=capture.programs;
  assert.equal(prologue.kind,'prologue');
  assert.equal(prologue.isPrologue,true);
  assert.equal(prologue.bufferRequests,1);
  assert.deepEqual(prologue.frames.map(frame=>[frame.percent,frame.complete]),[[0,false],[58,false],[100,true]]);
  for(const frame of prologue.frames.slice(0,2)){
    assert.equal(frame.status,buffer.rules.pending.replace('{percent}',String(frame.percent)));
    assert.equal(frame.hint,buffer.rules.pendingHint);
  }
  assert.equal(chapter.kind,'chapter');
  assert.equal(chapter.isPrologue,false);
  assert.equal(chapter.bufferRequests,0);
  assert.equal(chapter.frames.length,2);
  for(const frame of [prologue.frames[2],...chapter.frames]){
    assert.equal(frame.complete,true);
    assert.equal(frame.percent,100);
    assert.equal(frame.status,buffer.rules.ready);
    assert.equal(frame.hint,buffer.rules.readyHint);
    assert.deepEqual(frame.statusClasses,['ready']);
    assert.deepEqual(frame.hintClasses,['unlocked']);
  }
});
