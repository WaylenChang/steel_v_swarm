import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_frame_geometry.json'));
const data=JSON.parse(await read('data/campaign_frame_geometry.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic foreground retains frame, image, and border geometry',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/campaign_frame_geometry_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.rules.inset,.08);
  assert.equal(capture.rules.maxWidthRatio,.94);
  assert.equal(capture.rules.borderWidth,1);
  assert.equal(capture.rules.layoutUnits,64);
  assert.deepEqual(capture.rules.borderColor,[122/255,158/255,178/255,.28]);
  assert.equal(capture.cases.length,17);
  assert.equal(capture.cases.filter(row=>row.png).length,6);
  for(const row of capture.cases){
    assert.deepEqual(row.border,row.size[0]>row.size[1]?[0,1,0,1]:[0,0,0,0]);
    assert.ok(row.frame[2]>0&&row.frame[3]>0);
    assert.deepEqual(row.poses.map(pose=>pose.progress),[0,.5,1]);
  }
});
