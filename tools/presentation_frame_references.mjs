// Execute the original frame-budget and death-event statements, without rendering.
export function presentationFrameReferences(d, gameSource, BattleSim) {
  const text=gameSource.replace(/\r\n/g,'\n');
  const budget=/if \(this\._hitstop > 0\) \{[^\n]+\}/.exec(text)?.[0];
  const cap=/let dt = Math\.min\(([\d.]+), raw\)/.exec(text)?.[1];
  const heroes=/const HERO_KINDS = new Set\((\[[^\n]+\])\);/.exec(text)?.[1];
  const start=text.indexOf("    if (ev.e === 'die') {");
  const end=text.indexOf("      if (ev.kind === 'aasite')",start);
  if(!budget||!cap||!heroes||start<0||end<=start)throw new Error('Missing original hitstop/frame/death seams');
  const noop=()=>{};
  const scope={HERO_KINDS:new Function('return '+heroes)(),sceneIsPhysical:d.sceneIsPhysical,
    comicPop:noop,debrisBurst:noop,sideInfo:d.sideInfo};
  scope.HERO_KINDS=new Set(scope.HERO_KINDS);
  const death=new Function(...Object.keys(scope),'ev',text.slice(start,end)+'\n}');
  const step=new Function('raw',`let dt=Math.min(${cap},raw);${budget};return dt;`);
  const client=()=>({_hitstop:0,terrain:{heightAt:()=>0},_explosion:noop,_applyBlast:noop,scene:{},effects:[]});
  const deathSeconds={},deaths=[],deathEffects={},primitives=[];
  const capture=(kind,side,point,ground,symbolic)=>{
    const calls=[];
    const options=(type,x,y,z,opts={})=>{
      const row={type,point:[x,y,z],big:!!opts.big};
      if(type==='comic')row.hue=opts.hue??null;
      else row.accent=typeof opts.accent==='string'?parseInt(opts.accent.slice(1),16):opts.accent??null;
      calls.push(row);
    };
    const local={...scope,sideInfo:symbolic?()=>({color:-1}):d.sideInfo,
      comicPop:(_scene,_effects,x,y,z,opts)=>options('comic',x,y,z,opts),
      debrisBurst:(_scene,_effects,x,y,z,opts)=>options('mechanical',x,y,z,opts)};
    const state={...client(),terrain:{heightAt:()=>ground},
      _explosion(x,y,z,radius,color){calls.push({type:'explosion',point:[x,y,z],radius,color});},
      _applyBlast(x,y,z,radius){calls.push({type:'blast',point:[x,y,z],radius});}};
    death.call(state,...Object.values(local),{e:'die',kind,side,x:point[0],z:-point[2]});
    return calls;
  };
  for(const kind of new Set([...Object.keys(d.UNITS),...Object.keys(d.HAZARDS),'civilian','drone','robot','morph','unknown'])) {
    const state=client();death.call(state,...Object.values(scope),{e:'die',kind,x:0,z:0});
    deathSeconds[kind]=state._hitstop;deaths.push({kind,remaining:state._hitstop});
    deathEffects[kind]={};
    for(const side of ['', 'STEEL']) {
      deathEffects[kind][side?'side':'neutral']=capture(kind,side,[0,0,0],0,true);
      primitives.push({kind,side,point:[12,81,-9],ground:23,calls:capture(kind,side,[12,81,-9],23,false)});
    }
    for(const side of ['SWARM','SUPER','GUER','MILI','unknown'])
      primitives.push({kind,side,point:[12,81,-9],ground:23,calls:capture(kind,side,[12,81,-9],23,false)});
  }
  const traces=[];
  for(const actions of [
    [{raw:.016,kind:'base'},{raw:.016},{raw:.1},{raw:.1},{raw:.016}],
    [{raw:.8,kind:'tank'},{raw:.8},{raw:.8}],
    [{raw:0,kind:'tower'},{raw:0},{raw:.03,kind:'base'},{raw:.03,kind:'tank'},{raw:.1},{raw:.016},{raw:.016}],
    [{raw:.016,kind:'civilian'},{raw:.016,kind:'soldier'},{raw:.016,kind:'robot'},{raw:.06},{raw:.016,kind:'civilian'},{raw:.016}]
  ]) {
    const state=client(),frames=[];
    for(const action of actions) {
      const delta=step.call(state,action.raw);
      if(action.kind)death.call(state,...Object.values(scope),{e:'die',kind:action.kind,x:0,z:0});
      frames.push({...action,delta,remaining:state._hitstop});
    }
    traces.push(frames);
  }
  const kill=BattleSim.prototype._kill.toString(),killEnd=kill.indexOf('    if (t.civ) {');
  if(killEnd<0)throw new Error('Missing original general death publication seam');
  const publish=new Function('t','by',kill.slice(kill.indexOf('{')+1,killEnd));
  const reports=[];
  for(const kind of ['soldier','tank','heli','tower','base']) {
    const target={id:4,kind,side:'STEEL',x:3.25,z:-7.125},state={events:[]};
    publish.call(state,target,null);
    const room={ents:new Map(),visionUntil:{},_visionSources:()=>[],_frame:()=>({ev:state.events,sm:[],lt:[],ad:[]}),
      _tickN:1,creepUpg:{SWARM:[],STEEL:[]},_cuVer:0,_sgVer:0,siege:false,weatherScars:[],weatherSurface:{},
      nextWaveAt:0,t:0,wave:0,stats:{},over:false,winner:null};
    const snapshot=BattleSim.prototype.snapshotFor.call(room,'SWARM');
    reports.push({target,event:state.events[0],visibleEvents:snapshot.ev});
  }
  return {rules:{deathSeconds,deathEffects},fixtures:{presentationFrameDeaths:deaths,presentationFrameTraces:traces,presentationFrameReports:reports,deathPrimitives:primitives}};
}
