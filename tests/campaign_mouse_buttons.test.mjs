import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_mouse_buttons.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic uses browser mouse pointer lifetime',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.name),['right','middle','back','forward','side_then_left','wheel_during_hold','left_then_right','right_then_left']);
  for(const program of capture.programs){
    assert.equal(program.frames[0].events[0].type,'pointerdown');
    assert.equal(program.frames.at(-1).events[0].type,'pointerup');
    for(const [index,frame] of program.frames.entries()){
      assert.equal(frame.holding,index<program.frames.length-1,program.name);
      assert.equal(frame.holdStart,program.frames[0].holdStart,program.name);
      if(index>0&&index<program.frames.length-1)assert.deepEqual(frame.events,[],program.name);
    }
  }
});
