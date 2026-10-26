import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

export async function captureAudioMoveWaveforms(page,movement,original,{automation=false}={}) {
  assert.equal(typeof automation,'boolean');
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
  return await page.evaluate(async({movement,original,cases,automation})=>{
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
      let now=0;
      const clock={get currentTime(){return now;}};
      for(const key of ['createGain','createStereoPanner','createOscillator','createBiquadFilter','createBufferSource'])clock[key]=context[key].bind(context);
      const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:clock,_noise:buffer,
        _sfx:context.destination,_dead:false,lowPower:false,_move:{}});
      const voice=audio._moveVoice(fixture.category);
      // Begin both static and automated programs at the same source graph state.
      voice.g.gain.value=fixture.gain;voice.sp.pan.value=fixture.pan;
      if(voice.dry){voice.dry.gain.value=1-fixture.wet;voice.wet.gain.value=fixture.wet;}
      const commands=[];
      if(automation) {
        const record=(parameter,key,scale=1)=>{
          const schedule=parameter.setTargetAtTime.bind(parameter);
          parameter.setTargetAtTime=(target,time,tau)=>{
            commands.push({key,target:target/scale,time,tau});
            return schedule(target,time,tau);
          };
        };
        record(voice.g.gain,'gain');record(voice.sp.pan,'pan');
        for(const binding of voice.rate)record(binding.p,'rate',binding.base);
        if(voice.wet){record(voice.wet.gain,'wet');record(voice.dry.gain,'dry');}
        for(const action of [{time:.125,gain:.8,pan:-.7,wet:.9},{time:.375,gain:.4,pan:.9,wet:.1},{time:.625,gain:.9,pan:0,wet:.65}]) {
          now=action.time;
          audio.setMove(fixture.category,action.gain,action.pan,1,action.wet);
        }
        now=.875;audio._stopMove();
        const dry=commands.filter(command=>command.key==='dry'),wet=commands.filter(command=>command.key==='wet');
        if(dry.length!==wet.length||dry.some((command,index)=>command.time!==wet[index].time||command.tau!==wet[index].tau||Math.abs(command.target+wet[index].target-1)>Number.EPSILON))throw new Error('Original dry/wet targets are not complementary');
      }
      const rendered=await context.startRendering();
      waveforms.push({...fixture,...(automation?{commands:commands.filter(command=>command.key!=='dry')}:{}),frames,
        channels:[0,1].map(channel=>encode(rendered.getChannelData(channel)))});
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
  },{movement,original,cases,automation});
}
