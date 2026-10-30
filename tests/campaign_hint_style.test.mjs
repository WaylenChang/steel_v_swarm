import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_hint_style.json'));
const data=JSON.parse(await read('data/campaign_hint_style.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original campaign status and skip hint keep computed style',async()=>{
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.size),[[320,568],[720,720],[1440,900]]);
  for(const program of capture.programs){
    assert.deepEqual(program.states.map(state=>state.badges),[0,2]);
    for(const state of program.states){
      assert.equal(state.fontSize,capture.rules.hintFontSize);
      assert.equal(state.statusFontSize,capture.rules.statusFontSize);
      assert.deepEqual(state.color,capture.rules[state.ready?'readyColor':'pendingColor']);
    }
  }
});
