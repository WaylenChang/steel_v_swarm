// Execute active original carrier producers and the exact carrier phase in tick.
// Blast/CC are boundary spies; strike distribution and its RNG remain original.
export function carrierControllerReferences(d,BattleSim,config,makeRng) {
  const probeRng=makeRng(42),angles=[0,-0,1e-12,-1e-12];
  for(let i=-8;i<=8;i++)for(const offset of [-1e-12,0,1e-12]){
    const angle=i*Math.PI/4+offset;if(Math.abs(angle)<=Math.PI*2)angles.push(angle);
  }
  for(let i=0;i<512;i++)angles.push(probeRng()*Math.PI*2);
  const carrierLaunchMath=angles.map(angle=>({angle,sin:Math.sin(angle),cos:Math.cos(angle),
    x:Math.cos(angle)*35+234+58,z:Math.sin(angle)*35+178+48}));
  for(const row of carrierLaunchMath)row.distance=Math.hypot(row.x,row.z);
  const template=new BattleSim(config),tick=d.GAME.TICK_MS/1000;
  const seam=/this\._tickDecoys\(dt\);\s*this\._tickKamis\(dt\);\s*this\._tickHypers\(dt\);/.exec(BattleSim.prototype.tick.toString());
  if(!seam)throw Error('Original mixed carrier phase changed');
  const step=new Function('dt',seam[0]),carrierControllers=[];
  for(const [group,hyper]of ['t01','t09','m07'].entries())for(const superIndex of [-1,0,1,2])
  for(const reverse of [false,true])for(const mode of ['present','dead','missing','restored']){
    const characters=['s01','m06',hyper,'s01','m06'],peers=[42,7,19,101,93];
    const owners=characters.map((ch,index)=>{
      const superLevel=index===superIndex?19:null,level=superLevel==null?1:d.superCombatLvl(superLevel);
      return {id:index+1,pid:peers[index],ch,hero:true,kind:d.CHARACTERS[ch].kind,
        side:superLevel!=null?'SUPER':index>=3?'SWARM':'STEEL',superLevel,
        x:20+index*7,z:-30+index*3,y:12,ry:.7,hp:400,maxHp:1000,sp:80,maxSp:500,mp:1000,maxMp:1000,armor:12,
        dead:false,mods:[],buffs:{},abil:{light:level,heavy:level,def:level,atk:level},
        upg:{lw:0,hw:0,def:0,atk:0,hp:0,ar:0,sp:0,ch:0,...(superLevel==null?{}:{super:superLevel})}};
    });
    const s=Object.assign(Object.create(template),{t:10,over:false,events:[],ents:new Map(owners.map(h=>[h.id,h])),
      heroes:new Map(owners.map(h=>[h.pid,h])),squads:new Map(),curWeatherDyn:null,weatherSurface:null,curWeatherVec:{fog:0}});
    for(const h of owners){h.sq={pid:h.pid,bodies:[h],act:0,kamis:[],decoys:[]};s.squads.set(h.pid,h.sq);}
    let next=owners.length+1,active=0,draws=0;const trace=[];
    s._add=e=>{e.id=next++;e.maxHp=e.hp;e.cd=0;s.ents.set(e.id,e);return e;};
    s._unitLev=()=>0;s._applyCC=()=>{};
    for(const method of ['_kamiBoom','_decoyBoom','_hyperBoom','_atkArrive']){
      const original=BattleSim.prototype[method];
      s[method]=function(carrier,...args){const previous=active;active=carrier.id;
        try{return original.call(this,carrier,...args);}finally{active=previous;}};
    }
    s.events.push=function(...events){
      for(const e of events){
        if(e.e==='boom')trace.push({type:'boom',carrier:active,point:[e.x,e.y||0,-e.z],radius:e.r,side:e.side,
          sam:!!e.sam,kami:!!e.kami,hyper:!!e.hyper});
        if(e.e==='atkfx')trace.push({type:'arrival',carrier:active,owner:s.heroes.get(e.pid).id,
          point:[e.x,0,-e.z],fraction:e.frac,fx:e.fx});
      }
      return Array.prototype.push.apply(this,events);
    };
    const cast=BattleSim.prototype._castEffect;
    s._castEffect=function(h,A,x,z,fraction,nImp,...args){
      trace.push({type:'effect',carrier:active,owner:h.id,point:[x,0,-z],fraction,count:nImp??-1,fx:A.fx});
      return cast.call(this,h,A,x,z,fraction,nImp,...args);
    };
    s._blast=(h,A,x,z,y,level)=>trace.push({type:'blast',carrier:active,owner:h.id,point:[x,y,-z],damage:A.dmg,level});
    const snapshot=()=>({carriers:[...s.ents.values()].filter(e=>e.uA).map(e=>({id:e.id,kind:e.kind,
      position:[e.x,e.y||0,-e.z],yaw:e.ry||0,hp:e.hp})),
      rosters:owners.map(h=>({owner:h.id,active:[...h.sq.decoys,...h.sq.kamis,...(h.hypers||[])]
        .filter(e=>e.hp>0&&s.ents.has(e.id)).map(e=>e.id)})),trace:trace.splice(0),draws});
    const launchOrder=reverse?[4,3,2,1,0]:[0,1,2,3,4];
    const launches=launchOrder.map(index=>({owner:index+1,level:owners[index].abil.atk,
      point:[200+index*17,0,-(140+index*19)],origin:[-80+index*11,0,30+index*9]}));
    const inputs=owners.map(h=>({id:h.id,peer:h.pid,character:h.ch,side:h.side,position:[h.x,h.y,-h.z],
      hp:h.hp,max_hp:h.maxHp,shield:h.sp,max_shield:h.maxSp,armor:h.armor,superLevel:h.superLevel}));
    const previous=Math.random,random=makeRng(42);Math.random=()=>{draws++;return random();};
    let initial,frames=[];
    const affected=owners[(group+superIndex+5)%owners.length];
    try{
      for(const entry of launches){const h=owners[entry.owner-1],A=d.heroAbility(h.ch,'atk',entry.level);
        if(A.fx!=='strike'||!A.carrier||A.support)throw Error('Mixed fixture requires an active authored strike carrier');
        s._launchAtkCarrier(h,A,entry.point[0],-entry.point[2],{x:entry.origin[0],y:0,z:-entry.origin[2]});}
      s.events.length=0;initial=snapshot();
      for(let index=0;index<160;index++){
        s.t+=tick;
        const dead=mode==='dead'&&index===4,missing=['missing','restored'].includes(mode)&&index===4,
          restore=mode==='restored'&&index===12;
        if(dead){affected.hp=0;affected.dead=true;}
        if(missing)s.heroes.delete(affected.pid);
        if(restore)s.heroes.set(affected.pid,affected);
        step.call(s,tick);
        frames.push({now:s.t,delta:tick,dead,missing,restore,result:snapshot()});s.events.length=0;
        if(![...s.ents.values()].some(e=>e.uA))break;
      }
    }finally{Math.random=previous;}
    carrierControllers.push({inputs,launches,mode,affected:affected.id,initial,frames});
  }
  return {carrierControllers,carrierLaunchMath};
}
