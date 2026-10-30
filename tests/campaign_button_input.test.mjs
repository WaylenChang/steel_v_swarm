import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_button_input.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original button click bypasses buffering and rejects cancelled or outside gestures',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,hash] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash] of Object.entries(capture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.deepEqual(capture.programs.map(program=>program.name),['mouse-pending','mouse-ready','mouse-release-outside',
    'mouse-press-outside','touch-pending','touch-ready','touch-cancel','touch-release-outside',
    'touch-press-outside','touch-return-inside']);
  for(const program of capture.programs){
    const last=program.frames.at(-1);
    assert.equal(last.finishes,Number(['mouse-pending','mouse-ready','touch-pending','touch-ready'].includes(program.name)),program.name);
    assert.equal(last.warnings,0,program.name);
    assert.equal(last.holding,false,program.name);
    assert.equal(last.lastTap,program.name==='touch-press-outside'?1200:0,program.name);
  }
  for(const name of ['touch-press-outside','touch-return-inside']){
    const program=capture.programs.find(item=>item.name===name);
    assert.ok(program.frames[1].events.some(event=>event.type==='pointercancel'),name);
    assert.ok(program.frames.at(-1).events.some(event=>event.type==='touchend'),name);
    assert.ok(!program.frames.flatMap(frame=>frame.events).some(event=>event.type==='click'),name);
  }
});
