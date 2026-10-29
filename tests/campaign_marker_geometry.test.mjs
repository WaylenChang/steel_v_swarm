import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/campaign_marker_geometry.json'));
const data=JSON.parse(await read('data/campaign_marker_geometry.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original section marker reserves its bottom border and margin',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{bottomPadding:4,borderWidth:1,marginBottom:8,borderStyle:'solid',borderColor:[122/255,158/255,178/255,.15],gap:8});
  assert.equal(capture.programs.length,3);
  for(const program of capture.programs){
    assert.equal(program.scrollHeight,412);
    assert.deepEqual(program.sections,[{top:0,height:80,markerHeight:25,paragraphsTop:33},
      {top:104,height:100,markerHeight:25,paragraphsTop:33},{top:228,height:120,markerHeight:25,paragraphsTop:33}]);
    assert.equal(program.endTop,372);
    assert.deepEqual(program.emptySection,{height:50,paragraphsTop:33});
  }
});
