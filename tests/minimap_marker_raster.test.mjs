import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path),'utf8');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_marker_raster.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('marker rasters retain the original extracted callback and inputs',async()=>{
  assert.equal(capture.formatVersion,1);
  assert.deepEqual(Object.keys(capture.source.inputs),['tools/minimap_marker_raster_capture.mjs']);
  assert.deepEqual(Object.keys(capture.source.sourceInputs),['public/js/game.js','public/js/data.js','tools/audit_src.mjs']);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
});

test('browser captures cover original marker families and composition',()=>{
  assert.deepEqual(capture.size,[128,96]);
  assert.deepEqual(capture.background,[16,32,48]);
  assert.equal(capture.runtime.deviceScaleFactor,1);
  assert.ok(capture.runtime.browser&&capture.runtime.userAgent);
  assert.deepEqual(capture.cases.map(row=>row.name),['base-integer','base-fractional','tower-fractional',
    'hero-friendly','hero-enemy','npc-friendly','npc-enemy','heli-enemy','bunker-fractional',
    'arrow-rotated','inherited-stroke','overlap-and-clip']);
  for(const sample of capture.cases){
    const png=Buffer.from(sample.png,'base64');
    assert.deepEqual(png.subarray(0,8),Buffer.from('89504e470d0a1a0a','hex'));
    assert.equal(png.readUInt32BE(16),capture.size[0]);
    assert.equal(png.readUInt32BE(20),capture.size[1]);
    assert.equal(digest(png),sample.sha256,sample.name);
  }
});
