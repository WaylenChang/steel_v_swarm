import assert from 'node:assert/strict';

export function renderAudioMoveWave(tables,type,encodedFrequencies,rateModes=[]) {
  const f=Math.fround,size=tables.frames,rate=tables.sampleRate;
  assert.ok(Number.isSafeInteger(rate)&&rate>=8000&&rate<=384000);
  assert.ok([2048,4096,16384].includes(size));
  assert.equal(size,rate<=24000?2048:(rate<=88200?4096:16384));
  assert.equal(tables.ranges,Math.floor(.5+3*Math.log2(size)));
  const matches=tables.types.filter(item=>item.type===type);
  assert.equal(matches.length,1,'Unambiguous captured original oscillator shape');
  const selected=matches[0];
  assert.equal(selected.tables.length,tables.ranges);
  const waves=selected.tables.map(table=>{
    const bytes=Buffer.from(table.values,'base64');
    assert.equal(bytes.length,size*4);assert.equal(bytes.toString('base64'),table.values);
    return Float32Array.from({length:size},(_,index)=>{
      const value=bytes.readFloatLE(index*4);assert.ok(Number.isFinite(value));return value;
    });
  });
  const bytes=Buffer.from(encodedFrequencies,'base64');
  assert.equal(bytes.length%4,0);assert.equal(bytes.toString('base64'),encodedFrequencies);
  const frequencies=Float32Array.from({length:bytes.length/4},(_,index)=>bytes.readFloatLE(index*4));
  assert.equal(frequencies.length%4,0,'Complete source interpolation groups');
  if(rateModes.length) {
    assert.equal(rateModes.length*128,frequencies.length);
    for(const [quantum,mode]of rateModes.entries()) {
      assert.ok(mode===0||mode===1);
      if(!mode)assert.ok(frequencies.slice(quantum*128,quantum*128+128).every(value=>value===frequencies[quantum*128]));
    }
  }
  const increments=Float32Array.from(frequencies,value=>f(value* f(size/rate)));
  const output=new Float32Array(frequencies.length),scale=f(size/rate),inverse=f(1/scale),lowest=rate/size;
  let phase=0,quantumOrigin=0,lanes=[];
  for(let frame=0;frame<output.length;frame++) {
    const frequency=frequencies[frame];assert.ok(Number.isFinite(frequency)&&frequency>0&&frequency<rate/2);
    const step=increments[frame],constant=rateModes.length&&rateModes[Math.floor(frame/128)]===0;
    if(constant&&frame%128===0) {
      quantumOrigin=phase;
      lanes=[phase,phase+step,phase+f(2*step),phase+f(3*step)].map(value=>f(value)%size);
    }
    const position=constant&&step>=f(.3)?lanes[frame%4]:phase;
    const fundamental=constant?frequency:f(inverse*step),group=frame-frame%4;
    const linear=[0,1,2,3].every(offset=>increments[group+offset]>=f(.3));
    const pitch=Math.max(0,Math.min(tables.ranges-1,f(1+f(f(f(Math.log2(f(fundamental/lowest)))*1200)/400))));
    const high=Math.floor(pitch),low=Math.min(tables.ranges-1,high+1),blend=f(pitch-high),index=Math.floor(position);
    if(linear) {
      const fraction=f(f(position)-index);
      const sample=table=>f(table[index]+f(fraction*f(table[(index+1)&(size-1)]-table[index])));
      const higher=sample(waves[high]),lower=sample(waves[low]);
      output[frame]=f(higher+f(blend*f(lower-higher)));
    } else {
      const t=position-index,t2=t*t;
      const weights=step>=f(.3)?[]:(step>=f(.16)?[.5*t*(t-1),1-t2,.5*t*(t+1)]:
        [t*(t2-1)*(t-2)/24,-t*(t-1)*(t2-4)/6,(t2-1)*(t2-4)/4,-t*(t+1)*(t2-4)/6,t*(t2-1)*(t+2)/24]);
      let higher=0,lower=0;
      if(!weights.length) {
        const fraction=f(position)-index;
        higher=(1-fraction)*waves[high][index]+fraction*waves[high][(index+1)&(size-1)];
        lower=(1-fraction)*waves[low][index]+fraction*waves[low][(index+1)&(size-1)];
      }
      for(let point=0;point<weights.length;point++) {
        const offset=(index+point-(weights.length>>1))&(size-1);
        higher+=weights[point]*waves[high][offset];lower+=weights[point]*waves[low][offset];
      }
      output[frame]=f(f(1-blend)*higher+blend*lower);
    }
    phase=(phase+step)%size;
    if(constant&&step>=f(.3)&&frame%4===3) {
      lanes=lanes.map(value=>f(value+f(4*step))%size);
      if(frame%128===127)phase=(quantumOrigin+f(128*step))%size;
    }
  }
  return output;
}
