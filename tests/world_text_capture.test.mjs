import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {instrumentWorldTextCapture,captureWorldTextMesh} from '../tools/world_text_capture.mjs';
import {WorldSourceWriter} from '../tools/world_source_writer.mjs';

function mesh() {
  const attributes={position:{count:4},signGlow:{count:4,itemSize:1,getX:index=>index%2}};
  return {geometry:{getAttribute:name=>attributes[name]},userData:{signCount:1,signDropped:0,
    signTex:{image:{width:512,height:128}},nativeWorldText:{language:'local',scale:1,reserved:0,
      atlas:{width:512,height:128},styles:{stone:{cw:512,ch:128}},items:[{copy:{t:'Canal'},style:'stone'}]}}};
}

test('world-text observation instrumentation requires one unmodified source seam',()=>{
  const source='mesh.userData.signTex = tex;';
  const instrumented=instrumentWorldTextCapture(source);
  assert.ok(instrumented.startsWith(source));
  assert.match(instrumented,/language: visualPref/);
  assert.throws(()=>instrumentWorldTextCapture(''),/seam/);
  assert.throws(()=>instrumentWorldTextCapture(source+source),/seam/);
  assert.throws(()=>instrumentWorldTextCapture(instrumented),/seam/);
});

test('world-text capture retains constructor state, counts and exact glow independently',()=>{
  const original=mesh(),result=captureWorldTextMesh(original);
  assert.equal(result.count,1);
  assert.equal(result.dropped,0);
  assert.equal(result.scale,1);
  assert.deepEqual(result.glow,[0,1,0,1]);
  result.items[0].copy.t='Changed';
  assert.equal(original.userData.nativeWorldText.items[0].copy.t,'Canal');
  assert.equal(captureWorldTextMesh({userData:{},geometry:{getAttribute:()=>null}}),null);
  const outline=mesh();outline.userData={isOutline:true};
  assert.equal(captureWorldTextMesh(outline),null);
});

test('world-text capture rejects incomplete admission, atlas and vertex data',()=>{
  const missing=mesh();delete missing.userData.nativeWorldText;
  assert.throws(()=>captureWorldTextMesh(missing),/constructor/);
  const counts=mesh();counts.userData.signDropped=1;
  assert.throws(()=>captureWorldTextMesh(counts),/admission/);
  const atlas=mesh();atlas.userData.signTex.image.width=1024;
  assert.throws(()=>captureWorldTextMesh(atlas),/dimensions/);
  const bad=mesh(),get=bad.geometry.getAttribute;
  bad.geometry.getAttribute=name=>name==='signGlow'?{count:4,itemSize:1,getX:()=>NaN}:get(name);
  assert.throws(()=>captureWorldTextMesh(bad),/Nonfinite/);
  bad.geometry.getAttribute=name=>name==='signGlow'?{count:3,itemSize:1,getX:()=>0}:get(name);
  assert.throws(()=>captureWorldTextMesh(bad),/per-vertex/);
});

test('world-text constructor/glow metadata survives streamed world chunk publication',async()=>{
  const artifacts=fileURLToPath(new URL('../artifacts/sol/world-text-storage/',import.meta.url));
  await mkdir(artifacts,{recursive:true});
  const directory=await mkdtemp(join(artifacts,'run-'));
  const writer=new WorldSourceWriter(directory);
  const metadata=captureWorldTextMesh(mesh());
  await writer.append({positions:[0,0,0,1,0,0,1,1,0,0,1,0],sourceWorldText:metadata});
  const manifest=await writer.finish();
  const packed=await readFile(join(directory,'mesh_chunks',manifest.meshChunks[0].path.split('/').at(-1)));
  const rows=JSON.parse(gunzipSync(packed));
  assert.deepEqual(rows[0].sourceWorldText,metadata);
  assert.equal(manifest.meshCount,1);
});
