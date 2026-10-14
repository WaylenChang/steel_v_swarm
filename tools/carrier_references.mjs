// Original delivery producers/ticks are the oracle; Godot scenes own presentation and hit queries.
export function carrierReferences(d, BattleSim, config, makeRng) {
  const template=new BattleSim(config);
  const actor=(character='s01')=>({id:1,pid:'1',ch:character,hero:true,kind:d.CHARACTERS[character].kind,side:'STEEL',
    x:20,z:-30,y:12,ry:.7,hp:400,maxHp:1000,sp:80,maxSp:500,mp:1000,maxMp:1000,armor:12,dead:false,
    mods:[],buffs:{},abil:{light:1,heavy:1,def:1,atk:1},upg:{},acd:{},achg:{}});
  const context=h=>{
    const sq={pid:h.pid,bodies:[h],act:0,kamis:[],decoys:[]};h.sq=sq;
    const s=Object.assign(Object.create(template),{t:10,over:false,events:[],ents:new Map([[h.id,h]]),heroes:new Map([[h.pid,h]]),
      squads:new Map([[h.pid,sq]]),curWeatherDyn:null,weatherSurface:null,curWeatherVec:{fog:0}});
    let next=2;s._add=e=>{e.id=next++;e.maxHp=e.hp;e.cd=0;s.ents.set(e.id,e);return e;};
    return s;
  };
  const seeded=callback=>{
    const original=Math.random,random=makeRng(42);let draws=0;
    Math.random=()=>{draws++;return random();};
    try{return {value:callback(),draws};}finally{Math.random=original;}
  };
  const state=e=>{
    const result={kind:e.kind,x:e.x,y:e.y||0,z:e.z,yaw:e.ry||0,tx:e.pt?.x??e.tx,tz:e.pt?.z??e.tz,target:e.tid||0};
    if(e.uFrac!=null)result.fraction=e.uFrac;
    if(e.uA&&e.kind!=='decoy')result.count=e.uImp??-1;
    if(e.dieAt!=null)result.die_at=e.dieAt;
    if(e.uDrops)result.drops=e.uDrops.map(p=>({fraction:p.frac,count:p.n??-1}));
    if(e.nextBomb!=null)result.next_bomb=e.nextBomb;
    if(e.kind==='hyper')Object.assign(result,{x0:e.x0,y0:e.y0,z0:e.z0,ux:e.ux,uz:e.uz,distance:e.arcD,
      travel:e.trav,phase:e.phase,spin:e.spin,chase:!!e.chase,dive:e.dive||{},launch_at:e.launchAt||0});
    return result;
  };
  const carrierLaunch=[];
  for(const character of Object.keys(d.CHARACTERS))for(const level of [1,4])for(const near of [false,true]) {
    const h=actor(character),s=context(h),A=d.heroAbility(character,'atk',level);h.abil.atk=level;
    // Generic branches are parameterized by the original authored effect; unsupported effects stay gated natively.
    const point=near?[h.x,h.z]:[200,140],origin={x:-80,y:0,z:-30};
    if(near){origin.x=h.x;origin.z=h.z;origin.y=h.y;}
    const result=seeded(()=>s._launchAtkCarrier(h,A,...point,origin));
    carrierLaunch.push({character,level,near,point:[point[0],0,-point[1]],origin:[origin.x,origin.y,-origin.z],
      draws:result.draws,actors:[...s.ents.values()].filter(e=>e.uA).map(e=>({state:state(e),hp:e.hp,max_hp:e.maxHp,radius:d.hitR(e),height:d.hitH(e)}))});
  }
  const carrierMotion=[];
  for(const kind of ['kami','decoy','hyper'])for(const scenario of ['normal','timeout','owner_dead','owner_missing','deferred','tracking','tracking_lost','antipodal']) {
    const h=actor(kind==='kami'?'s01':kind==='decoy'?'m06':'t01'),s=context(h),A=d.heroAbility(h.ch,'atk',1);
    s._launchAtkCarrier(h,A,200,140,{x:-80,y:0,z:-30});
    const all=[...s.ents.values()].filter(e=>e.uA);
    const e=all[0];
    // Isolate one original actor without changing its flight law or settlement entry point.
    for(const other of all.slice(1))s.ents.delete(other.id);
    h.sq.kamis=kind==='kami'?[e]:[];h.sq.decoys=kind==='decoy'?[e]:[];h.hypers=kind==='hyper'?[e]:[];
    if(scenario==='timeout'&&kind!=='hyper')e.dieAt=10;
    if(scenario==='owner_dead'){h.dead=true;h.hp=0;}
    if(scenario==='owner_missing')s.heroes.delete(h.pid);
    if(scenario==='deferred'&&kind==='hyper')e.launchAt=11;
    if(scenario==='antipodal')e.ry=Math.atan2(-((e.pt?.x??e.tx)-e.x),(e.pt?.z??e.tz)-e.z)-Math.PI;
    const target={id:99,hero:true,kind:'drone',side:'SWARM',x:205,z:145,y:30,hp:100,dead:false};
    if(['tracking','tracking_lost'].includes(scenario)&&kind==='hyper'){s.ents.set(99,target);e.tid=99;}
    const initial=state(e),steps=[],arrivals=[];
    s._atkArrive=(v,x,z,frac=v.uFrac??1,nImp=v.uImp??null)=>arrivals.push({x,z,fraction:frac,count:nImp??-1});
    for(let index=0;index<160;index++) {
      const delta=index%3===0 ? .05 : .1;s.t+=delta;
      if(index===70&&scenario==='tracking_lost'){target.hp=0;target.dead=true;}
      if(index===50&&scenario==='tracking'){target.x+=20;target.z-=20;}
      const aim=e.tid&&target.hp>0&&!target.dead?{x:target.x,z:target.z,height:s._tgtY(target)}:null;
      if(kind==='kami')s._tickKamis(delta);else if(kind==='decoy')s._tickDecoys(delta);else s._tickHypers(delta);
      const alive=s.ents.has(e.id);
      steps.push({now:s.t,delta,target:aim,
        state:state(e),alive,arrivals:arrivals.splice(0)});
      if(!alive)break;
    }
    // Owner absence is tested at the shared delivery seam below; hypersonic owner rosters intentionally stop advancing when removed.
    carrierMotion.push({kind,scenario,initial,steps});
  }
  const carrierOrigin=[];
  for(const slot of ['def','atk'])for(const missing of [false,true])for(const dead of [false,true]) {
    const h=actor(),s=context(h);
    if(!missing) {
      for(const e of [{id:2,kind:'tower',side:'STEEL',x:25,z:-30,y:0,hp:dead?0:100},
        {id:3,kind:'base',side:'STEEL',x:15,z:-30,y:0,hp:100},{id:4,kind:'tower',side:'SWARM',x:20,z:-30,y:0,hp:100}])s.ents.set(e.id,e);
    }
    const o=s._launchOrigin(h,slot);
    carrierOrigin.push({slot,missing,dead,position:[o.x,o.y,-o.z]});
  }
  const carrierArrival=[];
  for(const missing of [false,true])for(const dead of [false,true])for(const fraction of [0,.25,1])for(const budget of [null,0,1,3]) {
    const h=actor(),s=context(h),A=d.heroAbility(h.ch,'atk',1),calls=[];
    h.dead=dead;if(missing)s.heroes.delete(h.pid);
    s._castEffect=(owner,definition,x,z,frac,nImp)=>calls.push({owner:owner.id,fx:definition.fx,x,z,fraction:frac,count:nImp??-1});
    s._atkArrive({pid:h.pid,side:h.side,uA:A,uFrac:fraction,uImp:budget},30,-40);
    carrierArrival.push({missing,dead,fraction,budget,calls});
  }
  const carrierMath=[];
  for(const kind of ['drone','morph','robot'])for(const effect of ['strike','heal','summon','emp','buff'])for(const total of [0,1,2,5,8,12.5]) {
    const n=d.atkParts(kind,effect);
    carrierMath.push({kind,effect,total,count:n,parts:Array.from({length:12},(_,i)=>d.atkPartN(total,n,i))});
  }
  const carrierStrike=[];
  for(const character of ['s01','m06','t01','t09','m07'])for(const fraction of [0,.25,1])for(const count of [null,0,1,3]) {
    const h=actor(character),s=context(h),A=d.heroAbility(character,'atk',1),hits=[];
    s._blast=(_owner,definition,x,z,y,level)=>hits.push({x,z,y,level,damage:definition.dmg});
    s._applyCC=()=>{};
    const result=seeded(()=>s._castEffect(h,A,30,-40,fraction,count));
    carrierStrike.push({character,fraction,count,draws:result.draws,hits});
  }
  const carrierInterceptions=[];
  for(const character of ['s01','m06','t01','t09','m07']) {
    const h=actor(character),s=context(h),A=d.heroAbility(character,'atk',1),enemy=actor('t05');
    Object.assign(enemy,{id:99,pid:'99',side:'SWARM',money:100,kn:0});s.heroes.set(enemy.pid,enemy);s.ents.set(enemy.id,enemy);
    seeded(()=>s._launchAtkCarrier(h,A,200,140,{x:-80,y:0,z:-30}));
    const e=[...s.ents.values()].find(e=>e.uA);let effects=0,blasts=0;
    s._castEffect=()=>effects++;s._blast=()=>blasts++;
    s._damage(e,e.hp+1,enemy,0,0,{type:'gun'});
    carrierInterceptions.push({character,kind:e.kind,present:s.ents.has(e.id),earned:enemy.money-100,score:enemy.kn,effects,blasts});
  }
  return {rules:{hp:{kami:d.kamiHp(),decoy:d.decoyHp(),hyper:d.hyperHp()}},
    fixtures:{carrierLaunch,carrierMotion,carrierOrigin,carrierArrival,carrierMath,carrierStrike,carrierInterceptions}};
}
