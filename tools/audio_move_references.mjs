export function audioMoveReferences(text) {
  const {GameAudio,MOVE}=new Function(text.replace(/^import .*$/gm,'').replace(/^export /gm,'')+'\nreturn {GameAudio,MOVE:_MOVE};')();
  const method=GameAudio.prototype.setMove.toString(),stop=GameAudio.prototype._stopMove.toString();
  const scalar=(body,pattern)=>{const match=pattern.exec(body);if(!match)throw new Error('Missing original permanent movement seam: '+pattern);return Number(match[1]);};
  const timing={creationThreshold:scalar(method,/gain > ([\d.]+)/),gainFloor:scalar(method,/Math.max\(([\d.]+)/),
    timeConstant:scalar(method,/\(gain, 0, 1\) \*[^\n]+, t, ([\d.]+)/),
    minimumRate:scalar(method,/const r = _clamp\(rate, ([\d.]+)/),maximumRate:scalar(method,/const r = _clamp\(rate, [\d.]+, ([\d.]+)/),
    stopTimeConstant:scalar(stop,/setTargetAtTime\([\d.]+, t, ([\d.]+)/)};
  function recorder(low=false,unlocked=true){
    const nodes=[],connections=[],references=new WeakMap();
    const parameter=(node,key,value)=>{
      const param={value,setTargetAtTime(target,time,tau){this.events.push({target,time,tau});},events:[]};
      references.set(param,{node,parameter:key});return param;
    };
    const context={currentTime:0};
    for(const kind of ['createGain','createStereoPanner','createOscillator','createBiquadFilter','createBufferSource'])context[kind]=()=>{
      const node={kind,starts:[],connect(target){connections.push({from:nodes.indexOf(this),to:references.get(target)});},start(...values){this.starts.push(values);}};
      const index=nodes.length;references.set(node,index);nodes.push(node);
      for(const [key,value]of Object.entries(kind==='createGain'?{gain:1}:kind==='createStereoPanner'?{pan:0}:kind==='createOscillator'?{frequency:440,detune:0}:kind==='createBiquadFilter'?{frequency:350,Q:1,gain:0,detune:0}:{playbackRate:1,detune:0}))node[key]=parameter(index,key,value);
      return node;
    };
    const output={};references.set(output,'sfx');
    const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:unlocked?context:null,_sfx:output,_noise:{},_dead:false,_move:{},lowPower:low,_sfxLoaded:true});
    const snapshot=()=>Object.fromEntries(Object.entries(audio._move).map(([category,voice])=>[category,{
      gain:voice.g.gain.events.at(-1)??null,pan:voice.sp.pan.events.at(-1)??null,
      rate:voice.rate.map(item=>({base:item.base,...item.p.events.at(-1)})),
      wet:voice.wet?.gain.events.at(-1)??null,dry:voice.dry?.gain.events.at(-1)??null}]));
    const graph=category=>{
      const voice=audio._moveVoice(category);
      if(voice.rate.some(item=>Math.abs(item.p.value-item.base)>1e-12))throw new Error('Unsupported original initial movement rate ratio');
      if(voice.dry&&voice.wet&&Math.abs(voice.dry.gain.value+voice.wet.gain.value-1)>1e-12)throw new Error('Unsupported original initial dry/wet movement weights');
      return {nodes:nodes.map((node,index)=>({id:index,kind:node.kind,...(node.type?{type:node.type}:{}),
        ...(node.loop!==undefined?{loop:node.loop}:{}),...(node.buffer?{buffer:'sharedNoise'}:{}),starts:node.starts,
        parameters:Object.fromEntries(Object.entries(node).filter(([,value])=>value&&typeof value==='object'&&'events'in value).map(([key,value])=>[key,{initial:value.value,events:[]}]))})),
        connections,g:references.get(voice.g),pan:references.get(voice.sp),dry:voice.dry?references.get(voice.dry):null,wet:voice.wet?references.get(voice.wet):null,
        rate:voice.rate.map(item=>({parameter:references.get(item.p),base:item.base}))};
    };
    return {audio,context,snapshot,graph};
  }
  const graphs=Object.fromEntries(['rotor','engine','wingflap','stomp'].map(category=>[category,recorder().graph(category)]));
  const programs=[];
  for(const category of Object.keys(graphs))for(const low of [false,true])for(const unlocked of [false,true]){
    const capture=recorder(low,unlocked),frames=[];
    const actions=[['set',0,0,1,0],['set',.002,0,1,0],['set',.002001,0,1,0],['set',.8,-2,.1,-.5],
      ['set',.9,.4,2.5,.75],['low',true],['set',1,1,1,1],['low',false],['set',0,0,1,0],['stop']];
    for(const action of actions){
      capture.context.currentTime+=.1;
      if(action[0]==='set')capture.audio.setMove(category,...action.slice(1));
      else if(action[0]==='low')capture.audio.setLowPower(action[1]);
      else capture.audio._stopMove();
      frames.push({action,time:capture.context.currentTime,result:capture.snapshot()});
    }
    programs.push({category,low,unlocked,frames});
  }
  return {timing,graphs,fixtures:{audioMoveLifecycle:programs}};
}
