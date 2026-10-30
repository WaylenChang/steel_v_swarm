import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/spectator_hud_defaults.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original spectator HUD retains null and zero defaults',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs)){
    const bytes=await read(path);
    assert.equal(digest(path.endsWith('.mjs')?bytes.toString().replace(/\r\n?/g,'\n'):bytes),expected,path);
  }
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.deepEqual(capture.programs.map(row=>row.name),['missing','nulls','zeroes','partial-cooldowns','negative-values','nan-cooldown']);
  for(const program of capture.programs){
    assert.equal(program.result.light.ammo,null);
    assert.equal(program.result.heavy.ammo,null);
    assert.equal(program.result.lift,null);
    assert.equal(program.result.mobil,null);
    assert.equal(program.result.morph,null);
  }
  for(const program of capture.programs.slice(0,3)){
    assert.equal(program.result.mp,0);
    assert.equal(program.result.mm,1);
    assert.equal(program.result.msp,1);
    assert.equal(program.result.upg,null);
    assert.equal(program.result.def.cd,0);
  }
  const partial=capture.programs[3].result;
  assert.deepEqual(partial.upg,{});
  assert.equal(partial.def.cd,0);
  assert.equal(partial.atk.cd,2.5);
  const negative=capture.programs[4].result;
  assert.equal(negative.def.cd,-1);
  assert.equal(negative.mp,-5);
  assert.equal(negative.def.ready,false);
  assert.equal(capture.programs[5].result.def.cd,0);
  assert.equal(capture.programs[5].result.def.ready,true);
});
