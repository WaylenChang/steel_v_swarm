import assert from 'node:assert/strict';

// Offline Chromium wave-table extraction; runtime synthesis remains GDScript.
export async function captureAudioMoveWaves(page,sampleRate,types) {
  assert.ok(Number.isSafeInteger(sampleRate)&&sampleRate>=8000&&sampleRate<=384000);
  assert.ok(Array.isArray(types)&&types.length&&new Set(types).size===types.length);
  assert.ok(types.every(type=>['sine','square','sawtooth'].includes(type)));
  return await page.evaluate(async({sampleRate,types})=>{
    const f=Math.fround,size=sampleRate<=24000?2048:(sampleRate<=88200?4096:16384),half=size/2;
    const ranges=Math.floor(.5+3*Math.log2(size));
    const encode=values=>{
      const bytes=new Uint8Array(values.length*4),view=new DataView(bytes.buffer),parts=[];
      values.forEach((value,index)=>view.setFloat32(index*4,value,true));
      for(let offset=0;offset<bytes.length;offset+=8192)parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
      return btoa(parts.join(''));
    };
    const render=async(type,coefficients,normalize=false)=>{
      const context=new OfflineAudioContext(1,size*2,sampleRate),oscillator=context.createOscillator();
      // Half a table entry per sample selects the unculled table; even samples hit exact entries.
      oscillator.frequency.value=sampleRate/size/2;
      if(f(f(oscillator.frequency.value)*f(size/sampleRate))!==.5)throw new Error('Unavailable exact wave-table read rate');
      if(coefficients)oscillator.setPeriodicWave(context.createPeriodicWave(new Float32Array(half),coefficients,{disableNormalization:!normalize}));
      else oscillator.type=type;
      oscillator.connect(context.destination);oscillator.start();
      const values=(await context.startRendering()).getChannelData(0);
      return Float32Array.from({length:size},(_,index)=>values[index*2]);
    };
    const output=[];
    for(const type of types) {
      if(!['sine','square','sawtooth'].includes(type))throw new Error('Unsupported original movement oscillator type');
      const coefficients=new Float32Array(half);
      for(let harmonic=1;harmonic<half;harmonic++) {
        const factor=f(2/f(harmonic*f(Math.PI)));
        coefficients[harmonic]=type==='sine'?(harmonic===1?1:0):
          (type==='square'?(harmonic%2?f(2*factor):0):factor*(harmonic%2?1:-1));
      }
      const original=await render(type),normalized=await render(type,coefficients,true);
      for(let index=0;index<size;index++)if(original[index]!==normalized[index])
        throw new Error('Custom Fourier coefficients differ from original '+type+' at '+index);
      const raw=await render(type,coefficients);
      const peak=raw.reduce((maximum,value)=>Math.max(maximum,Math.abs(value)),0);
      if(!Number.isFinite(peak)||peak<=0)throw new Error('Invalid original normalization peak');
      const normalizationScale=f(1/(peak*2)),tables=[];
      for(let range=0;range<ranges;range++) {
        const partials=Math.floor(f(f(2**(-f(f(range*400)/1200)))*half));
        const selected=coefficients.slice();selected.fill(0,Math.min(half,partials+1));
        const values=await render(type,selected);
        for(let index=0;index<size;index++)values[index]=f(values[index]*f(normalizationScale*2));
        if(range===0)for(let index=0;index<size;index++)if(values[index]!==original[index])
          throw new Error('Original normalization differs at '+type+':'+index);
        tables.push({partials,values:encode(values)});
      }
      output.push({type,normalizationScale,tables});
    }
    const probes=[];
    const sequence=[1,1.875,1.8749,1.8751,3.5156248,3.515625,3.515626,4,15,46,100,200,1,sampleRate/2-1,sampleRate/6,2];
    const frequencies=Float32Array.from({length:512},(_,index)=>sequence[index%sequence.length]);
    for(const type of types) {
      const context=new OfflineAudioContext(1,frequencies.length,sampleRate),oscillator=context.createOscillator();
      const source=context.createBufferSource(),buffer=context.createBuffer(1,frequencies.length,sampleRate);
      oscillator.type=type;oscillator.frequency.value=0;buffer.copyToChannel(frequencies,0);
      source.buffer=buffer;source.connect(oscillator.frequency);oscillator.connect(context.destination);
      source.start();oscillator.start();
      probes.push({type,frames:frequencies.length,frequencyValues:encode(frequencies),
        values:encode((await context.startRendering()).getChannelData(0))});
    }
    return {sampleRate,frames:size,ranges,types:output,probes};
  },{sampleRate,types});
}
