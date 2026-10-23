import {readFile} from 'node:fs/promises';
import {join,resolve,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {captureSynthStems} from './audio_synth_capture.mjs';
import {audioMoveReferences} from './audio_move_references.mjs';
import {captureMoveBank} from './audio_move_capture.mjs';

export function audioCaptureBundles(audio) {
  return {
    audioClips:{formatVersion:audio.formatVersion,sampleRate:audio.sampleRate,samples:audio.samples,failures:audio.failures,source:audio.source},
    audioSynth:{formatVersion:audio.formatVersion,sampleRate:audio.sampleRate,sounds:audio.synth.sounds,source:audio.source,noiseSha256:audio.noise.sha256},
    audioMusic:{formatVersion:audio.formatVersion,sampleRate:audio.sampleRate,music:audio.music,source:audio.source,noiseSha256:audio.noise.sha256},
    audioMove:{formatVersion:audio.formatVersion,...audio.move,source:audio.source,noiseSha256:audio.noise.sha256},
    audioProbes:{formatVersion:audio.formatVersion,sampleRate:audio.sampleRate,noise:audio.noise,probes:audio.synthProbes,source:audio.source},
  };
}

export async function captureAudioClips(page,source) {
  const script=(await readFile(join(source,'public/js/audio.js'),'utf8')).replace(/\r\n?/g,'\n');
  const body=script.replace(/^import .*$/gm,'').replace(/^export /gm,'');
  const manifest=new Function(body+'\nreturn SFX_MANIFEST;')();
  const root=resolve(source,'public/audio');
  const files=await Promise.all(Object.entries(manifest).flatMap(([id,entry])=>(Array.isArray(entry)?entry:[entry]).map(async(url,index)=>{
    const path=resolve(source,'public',url);
    if(!path.startsWith(root+sep))throw new Error('Unsupported nonlocal source audio path: '+url);
    try {
      const bytes=await readFile(path);
      return {id,url,index,base64:bytes.toString('base64'),sha256:createHash('sha256').update(bytes).digest('hex')};
    } catch(error) {
      if(error.code!=='ENOENT')throw error;
      return {id,url,index,missing:true};
    }
  })));
  const result=await page.evaluate(async({body,files,synthStemSource,moveGraphs,moveBankSource})=>{
    const api=new Function('setInterval','clearInterval',body+'\nreturn {GameAudio,SFX_MANIFEST};')(()=>0,()=>{});
    const musicConfigurations=[];
    for(const mood of ['menu','battle']){
      const clock={currentTime:0,createGain:()=>({gain:{value:1,exponentialRampToValueAtTime(){}},connect(){}})};
      const audio=Object.assign(Object.create(api.GameAudio.prototype),{_ctx:clock,_dead:false,_proc:null,_master:{},bgmOn:true,bgmVol:1});
      audio._procStart(mood);
      musicConfigurations.push({mood,cfg:audio._proc.cfg,initialDelay:audio._proc.next});
    }
    const gcd=(a,b)=>b?gcd(b,a%b):a;
    let multiple=1;
    for(const configuration of musicConfigurations){
      const {cfg}=configuration;
      const harmonySteps=cfg.prog.length*16,melodySteps=cfg.scale.length*2;
      configuration.cycleSteps=harmonySteps/gcd(harmonySteps,melodySteps)*melodySteps;
      const denominator=cfg.bpm/gcd(15,cfg.bpm);
      multiple=multiple/gcd(multiple,denominator)*denominator;
    }
    // Integral sixteenth-note frames also keep repeated noise onsets aligned.
    // An integral full cycle alone can shift a drum onset by one sample.
    // Source note frequencies, durations, envelopes and harmony remain unchanged.
    const sampleRate=Math.round(48000/multiple)*multiple;
    if(sampleRate<8000||sampleRate>384000)throw new Error('Unsupported exact source music representation rate');
    const base64=bytes=>{
      const chunks=[];
      for(let i=0;i<bytes.length;i+=8192)chunks.push(String.fromCharCode(...bytes.subarray(i,i+8192)));
      return btoa(chunks.join(''));
    };
    function pcm(buffer,minimumFrames=buffer.length) {
      const channels=[];let last=minimumFrames-1;
      for(let channel=0;channel<buffer.numberOfChannels;channel++) {
        const values=buffer.getChannelData(channel);
        let peak=0,peakIndex=0;
        values.forEach((value,index)=>{if(!Number.isFinite(value))throw new Error('Nonfinite source audio sample');if(Math.abs(value)>peak){peak=Math.abs(value);peakIndex=index;}});
        const gain=peak>0?peak*32768/32767:1;
        const bytes=new Uint8Array(values.length*2),view=new DataView(bytes.buffer);
        let maximumError=0;
        for(let index=0;index<values.length;index++) {
          const value=peak>0?Math.max(-32767,Math.min(32767,Math.round(values[index]/peak*32767))):0;
          view.setInt16(index*2,value,true);
          if(value!==0)last=Math.max(last,index);
          maximumError=Math.max(maximumError,Math.abs(value/32768*gain-values[index]));
        }
        const indices=[...new Set([0,1,Math.floor(values.length/7),Math.floor(values.length/2),peakIndex,values.length-1])];
        channels.push({bytes,gain,peak,maximumError,probes:indices.map(index=>({index,value:values[index]}))});
      }
      const frames=Math.min(buffer.length,Math.max(1,last+1));
      return {sampleRate:buffer.sampleRate,frames,renderedFrames:buffer.length,
        channels:channels.map(({bytes,...channel})=>({...channel,pcm:base64(bytes.subarray(0,frames*2))}))};
    }
    const samples=Object.fromEntries(Object.keys(api.SFX_MANIFEST).map(id=>[id,[]])),failures={};
    const decoder=new OfflineAudioContext(2,1,sampleRate);
    for(const file of files) {
      const failure=kind=>{(failures[file.id]??=[]).push({url:file.url,index:file.index,kind});};
      if(file.missing){failure('missing');continue;}
      let buffer;
      try {
        const bytes=Uint8Array.from(atob(file.base64),character=>character.charCodeAt(0));
        buffer=await decoder.decodeAudioData(bytes.buffer);
      } catch {failure('decode');continue;}
      if(![1,2].includes(buffer.numberOfChannels))throw new Error('Unsupported source SFX channel count: '+file.url);
      samples[file.id].push({url:file.url,index:file.index,sha256:file.sha256,...pcm(buffer)});
    }
    const noiseContext=new OfflineAudioContext(1,1,sampleRate);
    const noiseAudio=Object.assign(Object.create(api.GameAudio.prototype),{_ctx:noiseContext});
    noiseAudio._buildNoise();
    const noise=noiseAudio._noise;
    const synthMethod=api.GameAudio.prototype._synth.toString();
    const ids=[...synthMethod.matchAll(/case '([^']+)'/g)].map(match=>match[1]);
    const probes=[];
    for(const id of ids)for(const gain of [.06,.4,1,1.4]) {
      const context=new OfflineAudioContext(2,sampleRate*2,sampleRate);
      const merger=context.createChannelMerger(2);merger.connect(context.destination);
      const nodeIds=new WeakMap(),nodes=[],connections=[],counts=[];
      nodeIds.set(merger,'output');
      const types={createGain:['gain'],createOscillator:['frequency','detune'],createBiquadFilter:['frequency','Q','gain','detune'],createBufferSource:['playbackRate','detune']};
      for(const [method,parameters]of Object.entries(types)) {
        const original=context[method].bind(context);
        context[method]=(...args)=>{
          const node=original(...args),record={id:nodes.length,kind:method,parameters:{},starts:[],stops:[]};
          nodes.push(record);nodeIds.set(node,record.id);
          for(const key of parameters) {
            const parameter=node[key],data={events:[]};record.parameters[key]=data;
            nodeIds.set(parameter,{node:record.id,parameter:key});
            for(const operation of ['setValueAtTime','linearRampToValueAtTime','exponentialRampToValueAtTime','setTargetAtTime','cancelScheduledValues']) {
              const originalParameter=parameter[operation].bind(parameter);
              parameter[operation]=(...values)=>{data.events.push({operation,values});return originalParameter(...values);};
            }
          }
          const connect=node.connect.bind(node);
          node.connect=(target,...indices)=>{connections.push({from:record.id,to:nodeIds.get(target),indices});return connect(target,...indices);};
          for(const operation of ['start','stop'])if(node[operation]) {
            const originalOperation=node[operation].bind(node);
            node[operation]=(...values)=>{record[operation==='start'?'starts':'stops'].push(values);return originalOperation(...values);};
          }
          record.snapshot=()=>{
            for(const key of parameters)record.parameters[key].initial=node[key].value;
            if('type'in node)record.type=node.type;
            if('loop'in node)record.loop=node.loop;
            if('buffer'in node&&node.buffer)record.buffer='sharedNoise';
            delete record.snapshot;
          };
          return node;
        };
      }
      const centered=context.createGain();centered.connect(merger,0,1);
      const audio=Object.assign(Object.create(api.GameAudio.prototype),{_ctx:context,_sfx:centered,_noise:noise,
        _bus(){const node=context.createGain();node.connect(merger,0,0);return node;},_count(duration){counts.push(duration);}});
      audio._synth(id,gain,0);
      if(counts.length!==1)throw new Error('Source synthesis voice count changed: '+id);
      const snapshotters=nodes.map(node=>node.snapshot);snapshotters.forEach(snapshot=>snapshot());
      const rendered=await context.startRendering();
      const minimumFrames=Math.ceil(counts[0]*sampleRate);
      probes.push({id,gain,reservationSeconds:counts[0],graph:{nodes,connections,centered:nodeIds.get(centered)},...pcm(rendered,minimumFrames)});
    }
    const synth=await new Function('return ('+synthStemSource+');')()(api,probes,noise,sampleRate,moveGraphs);
    const move=await new Function('return ('+moveBankSource+');')()(moveGraphs,noise);
    const music=[];
    for(const configuration of musicConfigurations){
      const period=configuration.cycleSteps*15/configuration.cfg.bpm;
      const periodFrames=Math.round(period*sampleRate);
      if(Math.abs(periodFrames-period*sampleRate)>1e-7)throw new Error('Nonintegral original music loop');
      const context=new OfflineAudioContext(1,periodFrames*3,sampleRate);
      let now=0;
      const clock={get currentTime(){return now;},createGain:()=>context.createGain(),
        createOscillator:()=>context.createOscillator(),createBiquadFilter:()=>context.createBiquadFilter(),
        createBufferSource:()=>context.createBufferSource()};
      const audio=Object.assign(Object.create(api.GameAudio.prototype),{_ctx:clock,_noise:noise,_master:context.destination,
        _dead:false,_proc:null,bgmOn:true,bgmVol:1});
      audio._procStart(configuration.mood);
      const proc=audio._proc;
      proc.out.gain.cancelScheduledValues(0);proc.out.gain.value=1;
      now=period*3;
      audio._procTick(proc);
      const rendered=await context.startRendering();
      const values=rendered.getChannelData(0);
      let maximumLoopError=0;
      for(let index=0;index<periodFrames;index++)maximumLoopError=Math.max(maximumLoopError,Math.abs(values[index+periodFrames]-values[index+periodFrames*2]));
      const stream=context.createBuffer(1,periodFrames*2,sampleRate);
      stream.copyToChannel(values.subarray(0,periodFrames*2),0);
      music.push({...configuration,loopBegin:periodFrames,loopEnd:periodFrames*2,periodSeconds:period,
        maximumLoopError,...pcm(stream)});
    }
    const noiseValues=noise.getChannelData(0),noiseBytes=new Uint8Array(noiseValues.length*4),noiseView=new DataView(noiseBytes.buffer);
    noiseValues.forEach((value,index)=>noiseView.setFloat32(index*4,value,true));
    return {sampleRate,samples,failures,music,synth,move,synthProbes:probes,noise:{sampleRate,frames:noiseValues.length,encoding:'float32le',data:base64(noiseBytes)}};
  },{body,files,synthStemSource:captureSynthStems.toString(),moveGraphs:audioMoveReferences(script).graphs,moveBankSource:captureMoveBank.toString()});
  result.noise.sha256=createHash('sha256').update(Buffer.from(result.noise.data,'base64')).digest('hex');
  return {...result,formatVersion:1,source:{audioSha256:createHash('sha256').update(script).digest('hex')},
    inputs:files.filter(file=>!file.missing).map(file=>'public/'+file.url)};
}
