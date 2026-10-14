export function supplyReferences(d,BattleSim,config,makeRng) {
  const template=new BattleSim(config),supplySizes=[],supplyPoints=[],supplyWaves=[],supplyRewards=[],supplyPickups=[],supplyOpen=[],supplySnapshots=[],supplyHeal=[],supplyBossCaps=[],supplyPower=[],supplyPublic=[];
  const seeded=(seed,callback)=>{
    const original=Math.random,random=makeRng(seed);let draws=0;
    Math.random=()=>{draws++;return random();};
    try{return {result:callback(),draws};}finally{Math.random=original;}
  };
  const normalizeEvent=event=>Object.fromEntries(Object.entries(event).map(([key,value])=>[
    ({r:'reward',sp:'shield',mp:'power',cd:'cooldown',v:'value',sz:'size'})[key]||key,value]));
  const initial={hp:100,maxHp:2000,sp:100,maxSp:300,mp:150,maxMp:100,money:10,acd:{def:11,atk:35},
    achg:{def:{max:2,rechargeAt:[8,11,40]},atk:{max:3,rechargeAt:[]}}};
  const actor=changes=>({id:1,pid:1,hero:true,ch:'t05',kind:'robot',side:'STEEL',x:0,z:0,y:0,dead:false,
    buffs:{},mods:[{k:'healAmp',m:1.4,until:20}],lightningScorch:1,...JSON.parse(JSON.stringify(initial)),...changes});
  const state=body=>({hp:body.hp,shield:body.sp,power:body.mp,money:body.money,cooldowns:body.acd,scorch:!!body.lightningScorch,
    charges:Object.fromEntries(Object.entries(body.achg||{}).map(([key,value])=>[key,{max:value.max,recharge_at:value.rechargeAt}]))});
  for(const sample of [0,.5,.75,.75000001,.95,.95000001,1]) {
    const original=Math.random;Math.random=()=>sample;
    try {supplySizes.push({sample,result:template._rollAirdropSize()});}finally{Math.random=original;}
  }
  const bounds={minX:-500,maxX:2000,minZ:-700,maxZ:700},lanes=[[[0,0],[1400,0]]],basePos={SWARM:[0,0],STEEL:[1400,0]};
  for(const domain of ['clear','tight','blocker'])for(const terrain of ['none','all','north'])for(const seed of [0,1,3,7,42,123456789]) {
    const area=domain==='tight'?{minX:-10,maxX:10,minZ:-10,maxZ:10}:bounds;
    const blockers=domain==='blocker'?[[700,0,10000]]:[];
    const sim=Object.assign(Object.create(template),{bounds:area,lanes,basePos,ents:new Map(),hazBlockers:blockers,
      _terrainBlocked:(x,z)=>terrain==='all'||terrain==='north'&&z>0});
    const fixture=seeded(seed,()=>sim._airdropPoint());
    supplyPoints.push({seed,terrain,state:{bounds:{...area,minZ:-area.maxZ,maxZ:-area.minZ},lanes:lanes.map(lane=>lane.map(([x,z])=>[x,-z])),
      bases:basePos,towers:[],blockers:blockers.map(([x,z,radius])=>({x,z:-z,radius}))},draws:fixture.draws,
      result:fixture.result?{x:fixture.result.x,z:-fixture.result.z}:null});
  }
  for(const players of [0,1,5,20])for(const live of [0,39,40])for(const mode of ['all','skip','none','integrated']) {
    let call=0;
    const points=Array.from({length:40},(_,index)=>mode==='none'||mode==='skip'&&index%2===0?null:{x:300+index,z:200+index});
    const sim=Object.assign(Object.create(template),{t:10,events:[],squads:new Map(Array.from({length:players},(_,id)=>[id,null])),
      airdrops:Array.from({length:live},(_,id)=>({id:-id-1})),bounds,lanes,basePos,ents:new Map(),hazBlockers:[],_terrainBlocked:()=>false});
    if(mode!=='integrated')sim._airdropPoint=()=>points[call++]??null;
    const fixture=seeded(42,()=>{sim._spawnAirdropWave();return {
      drops:sim.airdrops.slice(live).map(a=>({x:a.x,z:-a.z,size:a.s,multiplier:a.mul,ttl:a.ttl,land_at:a.landAt})),
      events:sim.events.map(e=>({count:e.n})),live:sim.airdrops.length};});
    supplyWaves.push({players,live,mode,points:points.map(p=>p?{x:p.x,z:-p.z}:null),draws:fixture.draws,result:fixture.result,
      state:{bounds:{...bounds,minZ:-bounds.maxZ,maxZ:-bounds.minZ},lanes:lanes.map(lane=>lane.map(([x,z])=>[x,-z])),bases:basePos,towers:[],blockers:[]}});
  }
  for(const reward of d.AIRDROP.REWARDS)for(const multiplier of [.5,1,2,3.5])for(const hp of [100,1950])for(const sp of [0,299])
    for(const mp of [0,150])for(const boss of [false,true])for(const charged of [false,true]) {
    const body=actor({hp,sp,mp,sq:boss?{boss:true,bossSeg:1}:null,achg:charged?JSON.parse(JSON.stringify(initial.achg)):undefined});
    const sim=Object.assign(Object.create(template),{t:10});
    const result=sim._grantReward(body,reward,multiplier);
    supplyRewards.push({reward,multiplier,input:{hp,shield:sp,power:mp,boss,charged},result:normalizeEvent(result),state:state(body)});
  }
  for(const lifetime of [.05,20])for(const landAt of [9.999,10,10.001])for(const altitude of [0,d.AIRDROP.MAX_Y,d.AIRDROP.MAX_Y+.001])
    for(const distance of [0,d.AIRDROP.PICK_R,d.AIRDROP.PICK_R+.001])for(const dead of [false,true]) {
    const bodies=[actor({x:distance,y:altitude,dead}),actor({id:2,pid:2,side:'SWARM'})],opened=[];
    const sim=Object.assign(Object.create(template),{t:10,airdrops:[{id:50,x:0,z:0,ttl:lifetime,landAt},{id:51,x:0,z:0,ttl:lifetime,landAt}],
      _allBodies:function*(){yield*bodies;},_openAirdrop:(body,a)=>opened.push({actor:body.id,drop:a.id})});
    sim._tickAirdrops(.125);
    supplyPickups.push({lifetime,landAt,altitude,distance,dead,opened,remaining:sim.airdrops.map(a=>({id:a.id,ttl:a.ttl}))});
  }
  for(const seed of [0,1,3,7,42,123456789])for(const size of d.AIRDROP.SIZES) {
    const body=actor(),sim=Object.assign(Object.create(template),{t:10,events:[]});
    const fixture=seeded(seed,()=>{sim._openAirdrop(body,{id:50,x:12,z:8,s:size.key,mul:size.mul});return {
      event:normalizeEvent(Object.fromEntries(Object.entries(sim.events[0]).filter(([key])=>!['e','pid','x','z'].includes(key)))),state:state(body)};});
    supplyOpen.push({seed,size:size.key,multiplier:size.mul,draws:fixture.draws,result:fixture.result});
  }
  for(const x of [-1.05,-.05,0,.05,1.05])for(const z of [-1.05,-.05,0,.05,1.05])for(const landAt of [9.999,10,10.001]) {
    const sim=Object.assign(Object.create(template),{t:10,_tickN:1,_frameTickN:0,events:[],missiles:[],loots:[],
      airdrops:[{id:50,x,z,s:'L',landAt}],_flushHurt:()=>{}});
    const a=sim._frame().ad[0];
    supplySnapshots.push({x,z:-z,landAt,result:{id:a.id,x:a.x,z:-a.z,size:a.s,landing:!!a.d}});
  }
  for(const segment of [-1,0,.5,1,2,3,4,5])supplyBossCaps.push({segment,result:d.bossSegCapF(segment)});
  for(const source of ['def','item','base','ooc'])for(const boss of [false,true])for(const hero of [false,true])
    for(const segment of [0,1,2,3])for(const hp of [100,1950])for(const amount of [0,1,1000]) {
    const body=actor({hero,hp,sq:boss?{boss:true,bossSeg:segment}:null});
    const sim=Object.assign(Object.create(template),{t:10});
    const healed=sim._healBody(body,amount,source);
    supplyHeal.push({source,boss,hero,segment,hp,amount,result:{hp:body.hp,healed,scorch:!!body.lightningScorch}});
  }
  const tick=BattleSim.prototype.tick.toString().replace(/\r\n/g,'\n');
  const begin=tick.indexOf('    for (const h of this.heroes.values())'),end=tick.indexOf('    // 機體層級',begin);
  if(begin<0||end<begin)throw new Error('Source power regeneration seam missing');
  const regenerate=new Function('chargeF','fluidFactor',`return function(dt){${tick.slice(begin,end)}}`)(d.chargeF,d.fluidFactor);
  for(const power of [0,99,100,150])for(const wet of [0,1,2])for(const delta of [.125,1]) {
    const body=actor({mp:power,maxMp:100,mpRegen:d.UNITS.robot.mpRegen,wet});
    regenerate.call({heroes:new Map([[1,body]]),_aliveN:()=>1,_chargeLvl:()=>2},delta);
    supplyPower.push({power,wet,delta,result:body.mp});
  }
  const publicEvents=[{e:'airfall',n:2},{e:'airdrop',pid:99,side:'SWARM',x:12,z:8,sz:'S',r:'money',v:50},{e:'relay',side:'SWARM',x:12,z:8}];
  const publicSim=Object.assign(Object.create(template),{t:10,_tickN:1,_frameTickN:0,events:publicEvents,missiles:[],loots:[],airdrops:[],_flushHurt:()=>{}});
  supplyPublic.push({events:[{type:'airfall',actor:0,count:2},{type:'airdrop',actor:99,peer:99,side:'SWARM',position:[12,0,-8],size:'S',reward:'money',value:50},
    {type:'relay',actor:99,side:'SWARM',position:[12,0,-8]}],types:publicSim._frame().ev.map(event=>event.e)});
  return {supplySizes,supplyPoints,supplyWaves,supplyRewards,supplyPickups,supplyOpen,supplySnapshots,supplyHeal,supplyBossCaps,supplyPower,supplyPublic};
}
