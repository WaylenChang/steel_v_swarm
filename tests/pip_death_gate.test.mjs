import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/pip_death_gate.json'));
const data=JSON.parse(await read('data/pip_death_gate.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original death inset prepares before its strict scissor size gate',async()=>{
  assert.deepEqual(data,{formatVersion:capture.formatVersion,source:capture.source,rules:capture.rules});
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.rules,{border:2,minimum:6});
  assert.deepEqual(capture.programs.map(row=>[row.name,row.prepared,row.rendered]),[
    ['desktop',true,true],['fractional',true,true],['exact-minimum',true,true],
    ['width-below',true,false],['height-below',true,false],['negative-position',true,true],
    ['alive',false,false],['transition',false,false],['game-over',false,false],['missing-side',false,false],
    ['missing-config',false,false],['missing-frame',false,false],['hidden-frame',false,false]]);
  for(const program of capture.programs)assert.equal(program.viewportBits.length,program.rendered?4:0);
});
