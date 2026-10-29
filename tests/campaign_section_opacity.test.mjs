import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_section_opacity.json'));
const data=JSON.parse(await read('data/campaign_section_opacity.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original active section transitions independently from inactive sections',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{inactive:.65,active:1,duration:.4,curve:[.25,.1,.25,1]});
  assert.deepEqual({opacity:capture.initial.opacity,animations:capture.initial.animations},{opacity:[1,.65,.65],animations:[0,0,0]});
  assert.deepEqual([...Buffer.from(capture.initial.png,'base64').subarray(0,8)],[137,80,78,71,13,10,26,10]);
  assert.equal(capture.programs.length,4);
  for(const program of capture.programs)for(const frame of program.frames){
    assert.equal(frame.opacity.length,capture.scenes.length);
    assert.deepEqual(frame.selected,capture.scenes.map((_,index)=>index===frame.index));
    if(frame.png)assert.deepEqual([...Buffer.from(frame.png,'base64').subarray(0,8)],[137,80,78,71,13,10,26,10]);
  }
});
