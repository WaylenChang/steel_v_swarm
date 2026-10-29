import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_heading.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic heading updates distinct badge, title and date fields',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.frames.map(frame=>frame.index),[0,2,4,4,-1,5,1]);
  for(const frame of capture.frames){
    const scene=capture.scenes[frame.active];
    assert.deepEqual([frame.tag,frame.badge,frame.title],[scene.tag,scene.badge,scene.title]);
    assert.deepEqual(frame.activeItems,capture.scenes.map((_,index)=>index===frame.active));
    assert.deepEqual(frame.activeSections,capture.scenes.map((_,index)=>index===frame.active));
  }
});
