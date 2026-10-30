import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_death_pose.json'));
const data=JSON.parse(await read('data/pip_death_pose.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original death-view eye retains measured top and ground fallback',async()=>{
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{defaultTop:14,sourceLift:2,groundLift:18});
  assert.equal(capture.cases.length,48);
  for(const sample of capture.cases){
    assert.equal(sample.surfaceCalls,sample.mode==='fallback'?1:0);
    assert.equal(sample.eyeFloat32Bits.length,3);
    assert.equal(sample.targetBits.length,3);
  }
  const samePoint=capture.cases.filter(row=>row.mode==='source'&&row.point.join(',')==='12,5,-9');
  const defaultEye=samePoint.find(row=>row.parameter===null).eyeBits;
  assert.deepEqual(samePoint.find(row=>row.parameter===0).eyeBits,defaultEye);
  assert.deepEqual(samePoint.find(row=>row.parameter==='NaN').eyeBits,defaultEye);
  assert.notDeepEqual(samePoint.find(row=>row.parameter===-0.125).eyeBits,defaultEye);
});
