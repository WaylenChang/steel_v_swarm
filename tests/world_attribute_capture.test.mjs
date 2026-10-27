import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureWorldAttribute} from '../tools/world_attribute_capture.mjs';
import {encodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const modulePath='out/forest_review/three.module.js';
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
assert.equal(createHash('sha256').update(await readFile(join(source,modulePath))).digest('hex'),provenance.inputs[modulePath]);
const THREE=await import(pathToFileURL(join(source,modulePath)).href);
const injected=new Function('return ('+captureWorldAttribute.toString()+');')();
const legacy=(geometry,name)=>{
  const attribute=geometry.getAttribute(name);
  if(!attribute)return [];
  const getters=['getX','getY','getZ','getW'].slice(0,attribute.itemSize);
  return Array.from({length:attribute.count},(_,index)=>getters.map(getter=>attribute[getter](index))).flat();
};
const words=values=>Buffer.from(new Float64Array(values).buffer).toString('hex');

test('original Three primitive attributes retain every scalar bit and browser transfer frame',()=>{
  const geometries=[new THREE.BoxGeometry(3,5,7),new THREE.PlaneGeometry(5,7,128,128),
    new THREE.SphereGeometry(3,128,64),new THREE.CylinderGeometry(3,5,7,64)];
  for(const geometry of geometries) {
    for(const name of ['position','normal','uv']) {
      const expected=legacy(geometry,name),actual=injected(geometry,name);
      assert.equal(words(actual),words(expected));
      // Complete wire frames, not sampled vertices, retain the former capture contract.
      assert.deepEqual(encodeSourceNumericPart(actual),encodeSourceNumericPart(expected));
    }
    geometry.dispose();
  }
});

test('normalized and interleaved attributes preserve original getter semantics and order',()=>{
  const geometry=new THREE.BufferGeometry();
  geometry.setAttribute('color',new THREE.Uint8BufferAttribute([0,255,128,13,255,0,64,32],4,true));
  geometry.setAttribute('normal',new THREE.Int16BufferAttribute([-32768,0,32767,16384,-7,1024],3,true));
  geometry.setAttribute('custom',new THREE.InterleavedBufferAttribute(new THREE.InterleavedBuffer(
    new Float32Array([999,-0,1.25,-2.5,888,999,0,-7.25,3.5,888]),5),3,1));
  for(const name of ['color','normal','custom'])assert.equal(words(injected(geometry,name)),words(legacy(geometry,name)));
  assert.ok(Object.is(injected(geometry,'custom')[0],-0));
  const calls=[];
  const attribute={count:2,itemSize:3};
  for(const [component,getter]of ['getX','getY','getZ'].entries())attribute[getter]=index=>{calls.push([index,component]);return index*3+component;};
  assert.deepEqual(Array.from(injected({getAttribute:()=>attribute},'position')),[0,1,2,3,4,5]);
  assert.deepEqual(calls,[[0,0],[0,1],[0,2],[1,0],[1,1],[1,2]]);
  geometry.dispose();
});

test('absent and empty attributes stay empty while unsupported or non-finite fields reject',()=>{
  const geometry=new THREE.BufferGeometry();
  assert.deepEqual(injected(geometry,'missing'),[]);
  geometry.setAttribute('position',new THREE.BufferAttribute(new Float32Array(),3));
  assert.deepEqual(Array.from(injected(geometry,'position')),[]);
  for(const value of [NaN,Infinity,-Infinity]) {
    geometry.setAttribute('position',new THREE.BufferAttribute(new Float64Array([value,0,0]),3));
    assert.throws(()=>injected(geometry,'position'),/Non-finite/);
  }
  for(const [count,itemSize]of [[1,0],[1,5],[-1,3],[.5,3]])
    assert.throws(()=>injected({getAttribute:()=>({count,itemSize})},'position'),/Unsupported/);
  geometry.dispose();
});
