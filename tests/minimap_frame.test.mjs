import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_frame.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const visible=frame=>({window:frame.window,crop:frame.crop,lanes:frame.lanes,markers:frame.markers,bunkers:frame.bunkers,
  missiles:frame.missiles,missileColour:frame.missileColour,arrow:frame.arrow,label:frame.label,labelColour:frame.labelColour});

test('minimap frame oracle retains only the extracted original inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/minimap_frame_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','public/index.html','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('original canvas retains one complete frame until its next due draw',()=>{
  assert.equal(capture.cases.length,5);
  assert.deepEqual(visible(capture.cases[1]),visible(capture.cases[0]));
  assert.deepEqual(visible(capture.cases[3]),visible(capture.cases[2]));
  assert.notDeepEqual(visible(capture.cases[2]),visible(capture.cases[1]));
  assert.notDeepEqual(visible(capture.cases[4]),visible(capture.cases[3]));
  assert.deepEqual(capture.cases.map(row=>row.due),[true,false,true,false,true]);
  assert.equal(capture.factionCases.length,3);
  assert.deepEqual(visible(capture.factionCases[1]),visible(capture.factionCases[0]));
  assert.notDeepEqual(visible(capture.factionCases[2]),visible(capture.factionCases[1]));
  assert.ok(capture.factionCases.every(row=>row.arrow&&row.missiles.length===1));
});
