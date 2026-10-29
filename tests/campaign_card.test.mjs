import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_card.json'));
const data=JSON.parse(await read('data/campaign_card.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original cinematic narrative card retains responsive viewport geometry',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/campaign_card_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/css/style.css','public/index.html']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules.landscape,{maxWidth:680,widthRatio:.86,maxHeight:240,heightRatio:.29,bottom:44});
  assert.deepEqual(capture.rules.portrait,{widthMargin:24,maxWidth:480,maxHeight:245,heightRatio:.3,bottom:48});
  assert.deepEqual(capture.rules.chrome,{
    landscape:{topHorizontal:24,top:14,bottomHorizontal:24,bottom:14,gap:0},
    portrait:{topHorizontal:14,top:8,bottomHorizontal:14,bottom:10,gap:4}});
  assert.equal(capture.rules.border,1);
  assert.equal(capture.rules.layoutUnits,64);
  assert.equal(capture.cases.length,15);
});
