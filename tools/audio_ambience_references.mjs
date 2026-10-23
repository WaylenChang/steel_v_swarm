export function audioAmbienceReferences(text) {
  const programs=[
    [['query',{}],['unlock'],['query',{}],['query',{water:0,forest:0}],['query',{}],['query',{forest:0}],['query',{tunnel:0,water:0}],['low',true],['query',{tunnel:0}],['low',false],['query',{tunnel:0}],['dispose'],['query',{water:0}]],
    [['low',true],['unlock'],['query',{water:0}],['query',{forest:0}],['low',false],['query',{water:.4995}],['query',{water:.499}],['query',{water:0}],['enabled',false],['query',{}],['enabled',true],['query',{}],['dispose']]
  ];
  return programs.map(actions=>{
    const elements=[];
    class Media {
      constructor(){this.paused=true;this.plays=0;this.pauses=0;elements.push(this);}
      play(){this.paused=false;this.plays++;return Promise.resolve();}
      pause(){this.paused=true;this.pauses++;}
    }
    const GameAudio=new Function('Audio',text.replace(/^import .*$/gm,'').replace(/^export /gm,'')+'\nreturn GameAudio;')(Media);
    const sfx={};
    const context={currentTime:1,createMediaElementSource:()=>({connect(){}}),createGain:()=>({gain:{value:1,
      setTargetAtTime(value,_time,tau){this.target=value;this.tau=tau;}},connect(destination){this.destination=destination;}})};
    const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:null,_dead:false,ambOn:true,lowPower:false,_amb:{},_sfx:sfx});
    const frames=[];
    for(const action of actions){
      const [op,value]=action;
      if(op==='query')audio.setAmbience(value);
      else if(op==='unlock')audio._ctx=context;
      else if(op==='low')audio.lowPower=value;
      else if(op==='enabled')audio.ambOn=value;
      else if(op==='dispose'){audio._stopAmbience();audio._dead=true;}
      frames.push({action,result:{beds:Object.fromEntries(Object.entries(audio._amb).map(([id,v])=>[id,
        {url:v.el.src,target:v.g.gain.target,initialGain:v.g.gain.value,tau:v.g.gain.tau,paused:v.el.paused,sfx:v.g.destination===sfx}])),
        created:elements.length,plays:elements.reduce((n,e)=>n+e.plays,0),pauses:elements.reduce((n,e)=>n+e.pauses,0)}});
    }
    return {frames};
  });
}
