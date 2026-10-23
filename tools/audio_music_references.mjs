// Execute the original lifecycle with inert media elements and manually advanced timers.
export function audioMusicReferences(text,trajClass) {
  const programs=[
    [['scene','menu'],['unlock'],['ready','menu'],['ticks',3],['scene','battle'],['ticks',2],['grace'],['ready','battle'],['ticks',12],['scene','menu'],['ticks',12],['dispose']],
    [['unlock'],['low',true],['scene','battle'],['grace'],['low',false],['ready','battle'],['ticks',2],['bgm',.9],['ticks',1],['ticks',20],['bgm_on',false],['ticks',2],['bgm_on',true],['ticks',24]],
    [['scene','menu'],['bgm_on',false],['unlock'],['ready','menu'],['ticks',1],['bgm_on',true],['ticks',12],['master_on',false],['ticks',12],['master_on',true],['ticks',12],['sfx',.3],['error','menu'],['ticks',1],['scene','unknown'],['grace'],['scene','battle'],['ready','battle'],['grace'],['ticks',12]],
    [['scene','unknown'],['low',true],['unlock'],['grace'],['scene','menu'],['ready','menu'],['ticks',2],['scene','battle'],['scene','menu'],['grace'],['ticks',12],['dispose'],['scene','battle'],['unlock']],
    [['scene','menu'],['unlock'],['ready','menu'],['ticks',12],['bgm','0'],['scene','menu'],['ticks',12],['bgm',false],['scene','menu'],['ticks',1],['bgm',null],['scene','menu'],['ticks',1],['bgm',0],['scene','menu'],['ticks',1]]
  ];
  return programs.map(actions=>{
    let serial=0,fade=null,grace=null,sfxGain=null;
    const intervals=new Map(),timeouts=new Map(),fallback=[];
    const timer=(table,kind)=>(callback,delay)=>{
      const id=++serial;table.set(id,{callback,delay});
      if(kind==='fade')fade=id;else grace=id;
      return id;
    };
    const clear=(table,kind)=>id=>{
      table.delete(id);
      if(kind==='fade'&&fade===id)fade=null;
      if(kind==='grace'&&grace===id)grace=null;
    };
    class Media {
      constructor(){this.volume=0;this.paused=true;this.listeners={};}
      get volume(){return this._volume;}
      set volume(value){
        const number=Number(value);
        if(!Number.isFinite(number)||number<0||number>1)throw new Error('Invalid source media volume');
        this._volume=number;
      }
      addEventListener(type,callback){this.listeners[type]=callback;}
      play(){this.paused=false;return Promise.resolve();}
      pause(){this.paused=true;}
    }
    const context={state:'running',destination:{},currentTime:0,
      createGain(){return {gain:{get value(){return sfxGain;},set value(v){sfxGain=v;}},connect(){}};},close(){}};
    const window={addEventListener(){},removeEventListener(){},AudioContext:class{constructor(){return context;}}};
    const factory=new Function('trajClass','lowPower','window','localStorage','location','Audio','setInterval','clearInterval','setTimeout','clearTimeout',
      text.replace(/^import .*$/gm,'').replace(/^export /gm,'')+'\nreturn GameAudio;');
    const GameAudio=factory(trajClass,()=>false,window,{getItem:()=>null,setItem(){}},undefined,Media,
      timer(intervals,'fade'),clear(intervals,'fade'),timer(timeouts,'grace'),clear(timeouts,'grace'));
    const audio=new GameAudio();
    audio._buildNoise=()=>{};
    audio._loadSamples=()=>audio._loadBgm();
    audio._procStop=()=>fallback.push({op:'fallback_stop'});
    audio._procStart=name=>fallback.push({op:'fallback_start',name});
    const frames=[];
    for(const action of actions) {
      fallback.length=0;
      const [op,value]=action;
      if(op==='scene')audio.setScene(value);
      else if(op==='unlock')audio.unlock();
      else if(op==='dispose')audio.dispose();
      else if(op==='low')audio.setLowPower(value);
      else if(op==='ready'||op==='error'){
        const element=audio._bgm[value]?.el;
        const type=op==='ready'?'canplaythrough':'error';
        const callback=element?.listeners[type];
        if(callback){delete element.listeners[type];callback();}
      }
      else if(op==='ticks'){
        for(let i=0;i<value;i++)if(fade!==null)intervals.get(fade)?.callback();
      }
      else if(op==='grace'){
        const callback=timeouts.get(grace)?.callback;
        timeouts.delete(grace);grace=null;
        callback?.();
      }
      else audio[{bgm:'setBgm',sfx:'setSfx',bgm_on:'setBgmOn',master_on:'setMasterOn'}[op]](value);
      frames.push({action,result:{scene:audio._scene||'',unlocked:audio._unlocked,disposed:audio._dead,low:audio.lowPower,
        fading:fade!==null,grace:grace!==null,sfxGain,
        tracks:Object.fromEntries(Object.entries(audio._bgm).map(([name,b])=>[name,{url:b.el.src,ok:b.ok,volume:b.el.volume,paused:b.el.paused}])),
        fallback:structuredClone(fallback)}});
    }
    return {frames};
  });
}
