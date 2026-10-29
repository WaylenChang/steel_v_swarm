import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_section_geometry.json'));
const data=JSON.parse(await read('data/campaign_section_geometry.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original crawl sections include bottom padding, border and margin in focus geometry',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{bottomPadding:16,borderWidth:1,marginBottom:24,borderStyle:'dashed',borderColor:[122/255,158/255,178/255,.16]});
  assert.equal(capture.programs.length,3);
  for(const program of capture.programs){
    assert.equal(program.scrollHeight,373);
    assert.deepEqual(program.sections,[{top:0,height:67},{top:91,height:87},{top:202,height:107}]);
    assert.equal(program.endTop,333);
    assert.equal(program.frames.length,7);
  }
});
