import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const read=path=>readFile(join(root,path));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const capture=JSON.parse(await read('tests/fixtures/minimap_lane_raster.json'));
const provenance=JSON.parse(await read('data/provenance.json'));

test('original minimap lane callback retains segmented strokes and rasters',async()=>{
  assert.equal(capture.formatVersion,1);
  for(const [path,expected] of Object.entries(capture.source.inputs))
    assert.equal(digest((await read(path)).toString().replace(/\r\n?/g,'\n')),expected,path);
  for(const [path,expected] of Object.entries(capture.source.sourceInputs)){
    assert.equal(provenance.inputs[path],expected,path);
    if(process.env.SVS_SOURCE)assert.equal(digest(await readFile(join(resolve(process.env.SVS_SOURCE),path))),expected,path);
  }
  assert.equal(capture.cases.length,10);
  for(const sample of capture.cases){
    const png=Buffer.from(sample.png,'base64');
    assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a',sample.name);
    assert.equal(digest(png),sample.sha256,sample.name);
    for(const stroke of sample.strokes){
      assert.ok(stroke.points.length>=2,sample.name);
      assert.equal(stroke.width,1.5);assert.equal(stroke.alpha,.7);
    }
  }
});
