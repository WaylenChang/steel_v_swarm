import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_double_click.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic double click fires after the second mouse release',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.name),['pending','ready','overlap','wheel']);
  for(const program of capture.programs.slice(0,2)){
    assert.deepEqual(program.frames.map(frame=>frame.holding),[true,false,true,false]);
    assert.deepEqual(program.frames.map(frame=>frame.finished),[0,0,0,program.ready?1:0]);
    assert.deepEqual(program.frames.map(frame=>frame.warnings),[0,0,0,program.ready?0:1]);
    assert.deepEqual(program.frames.at(-1).events.map(event=>event.type),['pointerup','click','dblclick']);
  }
  const overlap=capture.programs[2].frames;
  assert.deepEqual(overlap.map(frame=>frame.holding),[true,false,true,true,true,false]);
  assert.deepEqual(overlap.map(frame=>frame.warnings),[0,0,0,0,0,0]);
  assert.ok(overlap[4].events.every(event=>event.type!=='dblclick'));
  const wheel=capture.programs[3].frames;
  assert.deepEqual(wheel.map(frame=>frame.holding),[true,false,true,true,false]);
  assert.deepEqual(wheel.map(frame=>frame.warnings),[0,0,0,0,1]);
  assert.ok(wheel[4].events.some(event=>event.type==='dblclick'));
});
