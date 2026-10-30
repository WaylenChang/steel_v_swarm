import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_hint_badges.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original ready hint keeps separate styled badges through repeated state changes',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.hintWidth),[280,120,420]);
  for(const program of capture.programs){
    assert.deepEqual(program.states.map(state=>state.ready),[false,true,false,true]);
    assert.deepEqual(program.states[0],program.states[2]);
    assert.deepEqual(program.states[1],program.states[3]);
    for(const state of program.states){
      assert.equal(state.display,'flex');
      assert.equal(state.alignment,'center');
      assert.equal(state.gap,'6px');
      assert.equal(state.letterSpacing,'1.5px');
      assert.equal(state.unlocked,state.ready);
      assert.equal(state.badges.length,state.ready?2:0);
      assert.equal(state.text,state.ready?'雙擊 或 長按 任意處取消播放':'雙擊或長按跳過（緩衝下載中…）');
      for(const badge of state.badges){
        assert.equal(badge.background,'rgba(95, 208, 242, 0.15)');
        assert.equal(badge.borderColor,'rgba(95, 208, 242, 0.4)');
        assert.equal(badge.borderWidth,'1px');
        assert.equal(badge.borderRadius,'2px');
        assert.equal(badge.color,'rgb(165, 230, 251)');
        assert.deepEqual(badge.padding,['1px','6px','1px','6px']);
        assert.ok(badge.rect[2]>0 && badge.rect[3]>0);
      }
    }
    assert.deepEqual(program.states[1].badges.map(badge=>badge.text),['雙擊','長按']);
  }
  assert.deepEqual(capture.programs[0].states[1].badges.map(badge=>badge.rect),[[0,0,41,18],[66.5,0,41,18]]);
  assert.deepEqual(capture.programs[1].states.map(state=>state.height),[28,56,28,56]);
  assert.deepEqual(capture.programs[1].states[1].badges.map(badge=>badge.rect),[[0,12,27.5,32],[53,12,27.5,32]]);
});
