import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const fixture=JSON.parse(await read('tests/fixtures/pip_composition.json'));
const pip=JSON.parse(await read('tests/fixtures/pip.json'));
const provenance=JSON.parse(await read('data/provenance.json'));
const balance=JSON.parse(await read('data/balance.json'));

test('PiP raster capture retains the exact original methods and input identities',async()=>{
  assert.equal(fixture.formatVersion,1);
  assert.deepEqual(Object.keys(fixture.source.inputs),['tools/pip_composition_capture.mjs']);
  assert.deepEqual(Object.keys(fixture.source.sourceInputs),
    ['public/js/game.js','public/js/data.js','out/forest_review/three.module.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(fixture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(fixture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    assert.equal(pip.source.sourceInputs[path],expected,path);
    if(process.env.SVS_SOURCE)
      assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('PiP browser rasters cover every source layout and preserve renderer state',()=>{
  assert.equal(fixture.runtime.three,'160');
  assert.equal(fixture.runtime.webgl,'webgl2');
  assert.equal(fixture.runtime.deviceScaleFactor,1);
  assert.ok(fixture.runtime.browser&&fixture.runtime.renderer);
  assert.equal(fixture.runtime.color,balance.constants.SIDES.STEEL.color);
  assert.equal(fixture.cases.length,8);
  for(let index=0;index<fixture.cases.length;index++){
    const sample=fixture.cases[index],reference=pip.pipFrames[index<6?index:index===6?0:1];
    assert.deepEqual(sample.size,reference.size);
    assert.equal(sample.mode,index<6?(index%2?'low':'full'):index===6?'hidden_source':'power');
    assert.deepEqual(sample.selected,reference.selected.map(row=>row.id));
    assert.equal(sample.cockpit,index!==6);
    assert.deepEqual(sample.sourceVisibility,[{id:7,visible:index!==6},{id:9,visible:true}]);
    assert.equal(sample.scissor,false);
    assert.deepEqual(sample.viewport,[0,0,...sample.size]);
    assert.deepEqual(sample.client,sample.size);
    assert.deepEqual(sample.backing,sample.size);
    assert.equal(sample.clear,'000000');
    assert.equal(sample.alpha,1);
    const png=Buffer.from(sample.png,'base64');
    assert.deepEqual(png.subarray(0,8),Buffer.from('89504e470d0a1a0a','hex'));
    assert.equal(png.readUInt32BE(16),sample.size[0]);
    assert.equal(png.readUInt32BE(20),sample.size[1]);
    assert.equal(digest(png),sample.sha256);
  }
  assert.equal(fixture.cases[6].sha256,fixture.cases[0].sha256);
  assert.equal(fixture.cases[7].sha256,fixture.cases[1].sha256);
});

test('PiP source camera retains eye offsets through native float storage',()=>{
  assert.equal(fixture.poseCases.length,26);
  const witnesses={decoy:0,hero:0};
  for(const sample of fixture.poseCases){
    const offset=sample.decoy?pip.rules.DECOY_EYE:pip.rules.HERO_EYE;
    assert.deepEqual(sample.position,sample.position.map(Math.fround));
    assert.deepEqual(sample.draw.position,[sample.position[0],sample.position[1]+offset,sample.position[2]]);
    assert.deepEqual(sample.draw.positionFloat32,sample.draw.position.map(Math.fround));
    for(let index=0;index<3;index++){
      assert.equal(Buffer.from(sample.draw.positionBits[index],'hex').readDoubleLE(),sample.draw.position[index]);
      assert.equal(Buffer.from(sample.draw.positionFloat32Bits[index],'hex').readFloatLE(),sample.draw.positionFloat32[index]);
      assert.ok(Buffer.from(sample.draw.inversePositionFloat32Bits[index],'hex').readFloatLE()===Math.fround(sample.draw.inversePosition[index]));
    }
    for(let index=0;index<4;index++)
      assert.ok(Buffer.from(sample.draw.quaternionBits[index],'hex').readDoubleLE()===sample.draw.quaternion[index]);
    for(let index=0;index<9;index++){
      assert.ok(Buffer.from(sample.draw.basisFloat32Bits[index],'hex').readFloatLE()===Math.fround(sample.draw.basis[index]));
      assert.ok(Buffer.from(sample.draw.inverseBasisFloat32Bits[index],'hex').readFloatLE()===Math.fround(sample.draw.inverseBasis[index]));
    }
    assert.ok(Buffer.from(sample.yawBits,'hex').readDoubleLE()===sample.yaw);
    assert.equal(sample.draw.yaw,sample.yaw);
    const reference=pip.pipFrames.find(row=>row.size[0]===sample.size[0]&&row.size[1]===sample.size[1]);
    assert.deepEqual(sample.draw.rect,reference.draws[0].rect);
    if(Math.fround(sample.position[1]+Math.fround(offset))!==sample.draw.positionFloat32[1])
      witnesses[sample.decoy?'decoy':'hero']++;
  }
  assert.ok(witnesses.decoy>0,'decoy fixture must expose early Float32 rounding');
  assert.ok(witnesses.hero>0,'hero fixture must expose early Float32 rounding');
  const first=fixture.poseCases.find(row=>row.decoy&&row.yaw===1000000.01);
  const second=fixture.poseCases.find(row=>row.decoy&&row.yaw===1000000.02);
  assert.equal(Math.fround(first.yaw),Math.fround(second.yaw));
  assert.notDeepEqual(first.draw.basisFloat32Bits,second.draw.basisFloat32Bits);
});
