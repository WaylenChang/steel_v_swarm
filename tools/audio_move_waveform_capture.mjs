import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

export async function captureAudioMoveWaveforms(page,movement,original) {
  const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
  assert.equal(movement.scope,'original-movement-shared-sfx-rate');
  assert.equal(hash(original.replace(/\r\n?/g,'\n')),movement.source.audioSha256);
  const rate=movement.sampleRate,noise=movement.noise;
  assert.ok(Number.isSafeInteger(rate)&&rate>=8000&&rate<=384000);
  assert.equal(noise.sampleRate,rate);assert.equal(noise.frames,rate);
  const raw=Buffer.from(noise.values,'base64');
  assert.equal(raw.length,rate*4);assert.equal(raw.toString('base64'),noise.values);
  assert.equal(hash(raw),movement.noiseSha256);
  const cases=Object.keys(movement.graphs).flatMap(category=>(category==='stomp'?[0,.65,1]:[0])
    .map(wet=>({category,gain:.2,pan:.35,rate:1,wet})));
  return await page.evaluate(async({movement,original,cases})=>{
    const rate=movement.sampleRate,frames=rate;
    const GameAudio=new Function(original.replace(/^import .*$/gm,'').replace(/^export /gm,'')+';return GameAudio;')();
    const encode=values=>{
      const bytes=new Uint8Array(values.length*4),view=new DataView(bytes.buffer),chunks=[];
      values.forEach((value,index)=>view.setFloat32(index*4,value,true));
      for(let index=0;index<bytes.length;index+=8192)chunks.push(String.fromCharCode(...bytes.subarray(index,index+8192)));
      return btoa(chunks.join(''));
    };
    const decode=text=>{
      const bytes=Uint8Array.from(atob(text),value=>value.charCodeAt(0)),view=new DataView(bytes.buffer);
      return Float32Array.from({length:bytes.length/4},(_,index)=>view.getFloat32(index*4,true));
    };
    const noise=decode(movement.noise.values),waveforms=[],periodErrors={};
    for(const fixture of cases) {
      const context=new OfflineAudioContext(2,frames,rate),buffer=context.createBuffer(1,noise.length,rate);
      buffer.copyToChannel(noise,0);
      const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:context,_noise:buffer,
        _sfx:context.destination,_dead:false,lowPower:false,_move:{}});
      const voice=audio._moveVoice(fixture.category);
      // Static source graph states isolate DSP from the separately tested automation clock.
      voice.g.gain.value=fixture.gain;voice.sp.pan.value=fixture.pan;
      if(voice.dry){voice.dry.gain.value=1-fixture.wet;voice.wet.gain.value=fixture.wet;}
      const rendered=await context.startRendering();
      waveforms.push({...fixture,frames,channels:[0,1].map(channel=>encode(rendered.getChannelData(channel)))});
    }
    for(const captured of movement.oscillators) {
      const context=new OfflineAudioContext(1,frames,rate),oscillator=context.createOscillator();
      oscillator.type=captured.type;oscillator.frequency.value=captured.frequency;
      oscillator.connect(context.destination);oscillator.start();
      const actual=(await context.startRendering()).getChannelData(0),period=decode(captured.values);
      let phase=0,maximum=0;
      for(let index=0;index<frames;index++) {
        const position=phase*period.length,begin=Math.floor(position);
        const value=period[begin]+(period[(begin+1)%period.length]-period[begin])*(position-begin);
        maximum=Math.max(maximum,Math.abs(value-actual[index]));
        phase=(phase+captured.frequency/(rate*(captured.cycles||1)))%1;
      }
      periodErrors[captured.category+':'+captured.node]=maximum;
    }
    return {sampleRate:rate,frames,waveforms,periodErrors,noisePeak:noise.reduce((peak,value)=>Math.max(peak,Math.abs(value)),0)};
  },{movement,original,cases});
}
