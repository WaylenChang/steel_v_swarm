import {test} from 'node:test';
import assert from 'node:assert/strict';
import {encodeSourceNumericPart,decodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

test('binary source transfer retains every finite double bit and signed zero',()=>{
  const values=[-0,0,Number.MIN_VALUE,-Number.MIN_VALUE,Number.MAX_VALUE,-Number.MAX_VALUE,1/7,Math.PI];
  const frame=encodeSourceNumericPart(values),decoded=decodeSourceNumericPart(frame);
  assert.deepEqual(decoded.bytes,Buffer.from(new Float64Array(values).buffer));
  assert.deepEqual([decoded.rows,decoded.width,decoded.matrix],[values.length,1,false]);
  assert.ok(Object.is(values[0],-0));
});

test('matrix rank and row widths remain distinct from flat and single-column shapes',()=>{
  for(const values of [[[1,-0],[0,2]],[[1],[-0]],[[1,2,3,4]]]) {
    const decoded=decodeSourceNumericPart(encodeSourceNumericPart(values));
    assert.deepEqual(decoded.bytes,Buffer.from(new Float64Array(values.flat()).buffer));
    assert.deepEqual([decoded.rows,decoded.width,decoded.matrix],[values.length,values[0].length,true]);
  }
});

test('binary transfer retains both signs of every finite IEEE-754 exponent',()=>{
  const expected=Buffer.alloc(2047*2*8),values=[];
  for(let exponent=0;exponent<2047;exponent++)for(const sign of [0n,1n]) {
    const offset=values.length*8;
    expected.writeBigUInt64LE((sign<<63n)|(BigInt(exponent)<<52n)|0x123456789abcn,offset);
    values.push(expected.readDoubleLE(offset));
  }
  assert.deepEqual(decodeSourceNumericPart(encodeSourceNumericPart(values)).bytes,expected);
});

test('standalone browser encoder preserves complete multi-window numeric arrays',()=>{
  const browserEncoder=new Function('return ('+encodeSourceNumericPart.toString()+');')();
  const values=Array.from({length:65536},(_,index)=>index%3===0?-0:index/7);
  assert.deepEqual(browserEncoder(values),encodeSourceNumericPart(values));
  assert.deepEqual(decodeSourceNumericPart(browserEncoder(values)).bytes,Buffer.from(new Float64Array(values).buffer));
});

test('binary encoding rejects coercion, empty, ragged and nonfinite input',()=>{
  for(const values of [[],new Array(2),new Float64Array([1]),[NaN],[Infinity],[-Infinity],['1'],[null],[[1],[2,3]],[[]],[1,[2]],[new Array(268435456)]])
    assert.throws(()=>encodeSourceNumericPart(values),/source numeric transfer/);
});

test('binary decoding rejects malformed declarations, extents and noncanonical base64 before publication',()=>{
  const valid=encodeSourceNumericPart([0]);
  for(const frame of [null,[],{}, {...valid,encoding:'float64le'}, {...valid,extra:true},
    {...valid,shape:[]},{...valid,shape:[0]},{...valid,shape:[1.5]},{...valid,shape:[268435456]},
    {...valid,shape:[268435455,2]},{...valid,shape:[NaN]}, {...valid,shape:[1,1,1]},
    {...valid,data:valid.data.slice(1)}, {...valid,data:'!'.repeat(valid.data.length)},
    {...valid,data:valid.data.slice(0,-2)+'B='}])
    assert.throws(()=>decodeSourceNumericPart(frame),/source numeric transfer/);
});

test('receiver independently rejects nonfinite binary words',()=>{
  for(const value of [NaN,Infinity,-Infinity]) {
    const bytes=Buffer.alloc(8);bytes.writeDoubleLE(value);
    assert.throws(()=>decodeSourceNumericPart({encoding:'f64-le-base64',shape:[1],data:bytes.toString('base64')}),/Unsupported source numeric transfer value/);
  }
});
