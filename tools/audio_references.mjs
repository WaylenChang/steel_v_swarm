import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {audioMusicReferences} from './audio_music_references.mjs';
import {audioAmbienceReferences} from './audio_ambience_references.mjs';
import {audioSceneReferences} from './audio_scene_references.mjs';
import {audioMoveReferences} from './audio_move_references.mjs';
import {audioNativeReferences} from './audio_native_references.mjs';
import {localFireReferences} from './local_fire_references.mjs';

export async function audioReferences(source,d) {
  const scene=await audioSceneReferences(source,d);
  const localFire=await localFireReferences(source,d);
  const [text,html,main]=await Promise.all(['public/js/audio.js','public/index.html','public/js/main.js'].map(async path=>(await readFile(join(source,path),'utf8')).replace(/\r\n?/g,'\n')));
  const move=audioMoveReferences(text);
  const compile=new Function('trajClass','lowPower','setTimeout','window','localStorage','location','Math',
    text.replace(/^import .*$/gm,'').replace(/^export /gm,'')+
    '\nreturn {GameAudio,bgmUrl,ambienceMix,rules:{maxVoices:_MAX_VOICES,maxDistance:_MAX_DIST,referenceDistance:_REF_DIST,dedupSeconds:_DEDUP_S,masterDefault:_MASTER_DEF,sfxDefault:_SFX_DEF,bgmDefault:_BGM_DEF,rateJitter:_RATE_JIT,movement:_MOVE,samples:SFX_MANIFEST,music:BGM_MANIFEST,ambienceBase:AMB_BASE,ambience:AMBIENCE}};');
  const timers=[];
  const api=compile(d.trajClass,()=>false,(callback,delay)=>timers.push({callback,delay}),{addEventListener(){},removeEventListener(){}},{getItem:()=>null},undefined,Math);
  const scalar=pattern=>{const match=pattern.exec(text);if(!match)throw new Error('Missing source audio seam: '+pattern);return Number(match[1]);};
  const rules={...api.rules,scene:scene.rules,moveTiming:move.timing,moveGraphs:move.graphs,releaseGrace:scalar(/dur \* 1000 \+ ([\d.]+)/)/1000,
    sampleCountCap:scalar(/Math.min\(src.buffer.duration \/ rate, ([\d.]+)\)/),
    minimumGain:scalar(/_REF_DIST \/ \(_REF_DIST \+ dist\), ([\d.]+)/),
    defaultGain:api.GameAudio.prototype._spatial(null,0,0,null).gain,
    boom:{fallbackRadius:scalar(/ev.r \|\| ([\d.]+)/),divisor:scalar(/\(ev.r \|\| [\d.]+\) \/ ([\d.]+)/),
      minimum:scalar(/\(ev.r \|\| [\d.]+\) \/ [\d.]+, ([\d.]+)/),maximum:scalar(/\(ev.r \|\| [\d.]+\) \/ [\d.]+, [\d.]+, ([\d.]+)/)}};
  rules.synthesisIds=[...new Set([...api.GameAudio.prototype._synth.toString().matchAll(/case '([^']+)'/g)].map(match=>match[1]))];
  rules.musicTiming={graceSeconds:scalar(/}, (\d+)\);\s*for \(const \[n, b\] of Object.entries\(this\._bgm\)\)/)/1000,
    fadeSeconds:scalar(/if \(done\) clearInterval\(this\._bgmFade\);\s*}, (\d+)\)/)/1000,
    fadeStep:scalar(/want - cur, -([\d.]+),/),fadeTolerance:scalar(/Math.abs\(nv - want\) > ([\d.]+)/)};
  rules.ambienceTiming={creationThreshold:scalar(/low \|\| vol <= ([\d.]+)/),
    initialGain:scalar(/g = this\._ctx.createGain\(\); g.gain.value = ([\d.]+)/),
    timeConstant:scalar(/setTargetAtTime\(target, this\._ctx.currentTime, ([\d.]+)/)};
  rules.proceduralMusic={initialGain:scalar(/out.gain.value = ([\d.]+)/),minimumGain:scalar(/Math.max\(([\d.]+), this.bgmOn/),
    attackSeconds:scalar(/this.bgmVol : [\d.]+\), ctx.currentTime \+ ([\d.]+)/),
    volumeTimeConstant:scalar(/this.bgmVol : 0, this._ctx.currentTime, ([\d.]+)/),
    releaseGain:scalar(/p.out.gain.setTargetAtTime\(([\d.]+)/),releaseTimeConstant:scalar(/p.out.gain.setTargetAtTime\([\d.]+, t, ([\d.]+)/),
    retirementSeconds:scalar(/p.out.disconnect\(\);[^\n]+}, (\d+)\)/)/1000};
  rules.settings={};
  for(const [channel,name] of [['sfx','Sfx'],['bgm','Bgm']]) {
    const caption=new RegExp('<span class="set-label">([^<]+)</span>\\s*<button id="set'+name+'On"[^>]*aria-label="([^"]+)"').exec(html);
    const slider=new RegExp('<input id="set'+name+'Vol"[^>]+>').exec(html)?.[0];
    if(!caption||!slider)throw new Error('Missing original audio settings row: '+name);
    const attribute=key=>{const value=new RegExp(key+'="([^"]+)"').exec(slider)?.[1];if(value===undefined)throw new Error('Missing audio slider attribute: '+key);return value;};
    rules.settings[channel]={label:caption[1],toggleLabel:caption[2],volumeLabel:attribute('aria-label'),minimum:Number(attribute('min')),maximum:Number(attribute('max')),step:Number(attribute('step'))};
  }
  const masterLabels=/sound.setAttribute\('aria-label', audioOn \? '([^']+)' : '([^']+)'\)/.exec(main);
  if(!masterLabels)throw new Error('Missing original master audio toggle labels');
  rules.settings.masterOff=masterLabels[1];rules.settings.masterOn=masterLabels[2];
  const recorder=()=>Object.assign(Object.create(api.GameAudio.prototype),{_ctx:{currentTime:1},_dead:false,calls:[],_play(id,options){this.calls.push({id,...options});}});
  const calls=recorder();rules.ownFire={};rules.ui={};
  for(const slot of ['light','heavy']){calls.calls=[];calls.fire(null,slot,'STEEL');rules.ownFire[slot]=calls.calls[0].gain;}
  for(const id of ['click','buy','alert','unknown']){calls.calls=[];calls.ui(id);rules.ui[id]=calls.calls[0];}
  rules.eventGains={};
  for(const ev of [{e:'crit',pid:'you'},{e:'airfall'},{e:'buy',pid:'you'},{e:'relay'},{e:'lock',tpid:'you'}]) {
    calls.calls=[];calls.onEvent(ev,null,'you');rules.eventGains[ev.e]=calls.calls[0].gain;
  }
  const fire=[];
  for(const side of ['STEEL','SWARM','MERC'])for(const slot of ['light','heavy']) {
    fire.push({side,slot,definition:null,id:calls._fireId(null,slot,side)});
    for(const ch of Object.keys(d.CHARACTERS))for(const level of [1,4]) {
      const definition=d.heroWeapon(ch,slot,level);fire.push({side,slot,definition,id:calls._fireId(definition,slot,side)});
    }
  }
  const cameras=[null,{position:{x:3,y:12,z:-5},matrixWorld:{elements:[1,0,0,0,0,1,0,0,0,0,1,0,3,12,-5,1]}},
    {position:{x:3,y:12,z:-5},matrixWorld:{elements:[0,0,-1,0,0,1,0,0,1,0,0,0,3,12,-5,1]}}];
  const spatial=[];
  for(const camera of cameras)for(const [x,y,z] of [[3,null,-5],[29,null,-5],[243,12,-5],[243.001,12,-5],[3,252,-5],[-20,-8,45]])
    spatial.push({camera,x,y,z,result:calls._spatial(camera,x,z,y)});
  const events=[];
  const sourceEvents=[...['shot','plasma'].flatMap(e=>['you','other'].flatMap(pid=>['light','heavy'].flatMap(slot=>['STEEL','SWARM'].map(side=>({e,pid,slot,side}))))),
    ...['tower','base','tank','heli','bunker','robot','civilian'].map(kind=>({e:'die',kind})),
    ...[null,0,1,10,60,-3].map(r=>({e:'boom',r})),...['def','atk','ult'].map(slot=>({e:'cast',slot})),
    ...['you','other'].map(pid=>({e:'crit',pid})),{e:'sam'},{e:'sam',from:[20,30]},
    {e:'airfall'},{e:'airdrop'},...['you','other'].map(pid=>({e:'buy',pid})),{e:'relay'},
    ...['you','other'].map(tpid=>({e:'lock',tpid})),{e:'unknown'}];
  for(const camera of cameras)for(const ev of sourceEvents)for(const position of [{},{x:30,z:20,y:4},{x:999,z:999}]) {
    const event={...ev,...position};calls.calls=[];calls.onEvent(event,camera,'you');events.push({camera,event,result:calls.calls});
  }
  const ambience=[];
  const nativeEvents=audioNativeReferences(calls,cameras);
  for(const query of [{},Object.fromEntries(rules.ambience.map(a=>[a.id,0])),
    ...rules.ambience.flatMap(a=>[a.r-a.m,a.r-a.m/2,a.r,a.r+.001].map(value=>({[a.id]:value})))])
    ambience.push({query,result:api.ambienceMix(query)});
  const gates=[];
  for(const low of [false,true]) {
    const audio=Object.assign(Object.create(api.GameAudio.prototype),{_ctx:{currentTime:0},_last:new Map(),_active:0,lowPower:low,_buffers:{sample:[{}]},
      calls:[],_playSample(id,gain,pan){this.calls.push({id,gain,pan,layer:'sample'});},_synth(id,gain,pan){this.calls.push({id,gain,pan,layer:'synth'});}});
    const frames=[];
    for(const [now,id,active] of [[0,'sample',0],[.044,'sample',0],[.045,'sample',0],[.06,'sample',0],[.09,'sample',24],[.10,'sample',0],[.135,'sample',0],[.14,'other',0],[1,'other',25],[1.02,'other',0],[1.06,'other',0]]) {
      audio._ctx.currentTime=now;audio._active=active;audio.calls=[];audio._play(id,{gain:.7,pan:-.3});
      frames.push({now,id,active,result:audio.calls,last:Object.fromEntries(audio._last)});
    }
    gates.push({low,frames});
  }
  const counts=[];
  for(const duration of [.1,.24,1.5,2]) {
    timers.length=0;const audio=Object.assign(Object.create(api.GameAudio.prototype),{_active:0});audio._count(duration);
    const during=audio._active,delay=timers[0].delay;timers[0].callback();counts.push({duration,during,delay,after:audio._active});
  }
  const samples=[];
  for(const durations of [[.1],[.1,3],[.1,2,3,4]]) {
    let rolls=[],cursor=0,played;
    const math=Object.create(Math);math.random=()=>rolls[cursor++];
    const sampleApi=compile(d.trajClass,()=>false,(callback,delay)=>timers.push({callback,delay}),{},{},undefined,math);
    const audio=Object.assign(Object.create(sampleApi.GameAudio.prototype),{_active:0,_lastTake:new Map(),_buffers:{sample:durations.map((duration,index)=>({duration,index}))},
      _ctx:{createBufferSource(){played={playbackRate:{value:1},connect(){},start(){},disconnect(){}};return played;}},
      _bus:()=>({gain:{value:1},disconnect(){}})});
    const frames=[];
    for(const input of [[0,0],[0,.5],[.999999,.999999],[.999999,0],[.3,.7]]) {
      rolls=durations.length>1?input:[input[1]];cursor=0;timers.length=0;
      audio._playSample('sample',.7,-.3);
      frames.push({rolls,index:played.buffer.index,rate:played.playbackRate.value,duration:(timers[0].delay-60)/1000,draws:cursor});
    }
    samples.push({durations,frames});
  }
  const music=['menu','battle','unknown',''].flatMap(name=>[false,true].map(low=>({name,low,url:api.bgmUrl(name,low)})));
  const preferences=[];
  const savedStates=[null,{},[],false,'bad',{master:.4,muted:true},{master:4,muted:false},
    {sfxVol:null,sfxOn:false,master:.2},{sfxVol:.3,bgmVol:null,sfxOn:false,bgmOn:true},
    {sfxVol:'0.3',bgmVol:'bad',sfxOn:'yes',bgmOn:0}];
  const state=audio=>({sfxVol:audio.sfxVol,bgmVol:audio.bgmVol,sfxOn:audio.sfxOn,bgmOn:audio.bgmOn,masterOn:audio.masterOn()});
  for(const saved of savedStates) {
    const writes=[];
    const localApi=compile(d.trajClass,()=>false,()=>{}, {addEventListener(){},removeEventListener(){}},
      {getItem:()=>JSON.stringify(saved),setItem:(key,value)=>writes.push(JSON.parse(value))},undefined,Math);
    const audio=new localApi.GameAudio(),initial=state(audio),frames=[];
    for(const [method,value] of [['setSfx',null],['setSfx',false],['setSfx',true],['setSfx',-.5],['setSfx',2],['setSfx','0.4'],['setSfx',[]],
      ['setBgm',.7],['setBgm',.7],['setBgm',false],['setBgmOn',false],['setSfxOn',false],['setMasterOn',true],['setMasterOn',false],['setSfxOn',[]],['setBgmOn',{}]]) {
      audio[method](value);frames.push({method,value,result:structuredClone(state(audio)),writes:structuredClone(writes)});
    }
    preferences.push({saved,initial,frames});
  }
  const failedReads=[];
  for(const raw of ['', '{broken']) {
    const localApi=compile(d.trajClass,()=>false,()=>{}, {addEventListener(){},removeEventListener(){}},{getItem:()=>raw},undefined,Math);
    failedReads.push({raw,result:state(new localApi.GameAudio())});
  }
  const failedApi=compile(d.trajClass,()=>false,()=>{}, {addEventListener(){},removeEventListener(){}},
    {getItem:()=>null,setItem:()=>{throw new Error('fixture quota');}},undefined,Math);
  const failedAudio=new failedApi.GameAudio();failedAudio.setSfx(.2);failedAudio.setSfxOn(false);failedAudio.setBgmOn(true);failedAudio.setMasterOn(false);
  return {rules,fixtures:{...scene.fixtures,...move.fixtures,localFire,audioNativeEvents:nativeEvents,audioAmbienceLifecycle:audioAmbienceReferences(text),audioMusicLifecycle:audioMusicReferences(text,d.trajClass),audioFire:fire,audioSpatial:spatial,audioEvents:events,audioAmbience:ambience,audioGates:gates,audioCounts:counts,audioSamples:samples,audioMusic:music,audioPreferences:preferences,audioFailedReads:failedReads,audioFailedWrite:state(failedAudio)}};
}
