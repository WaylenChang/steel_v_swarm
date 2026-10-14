// Counters come from original death settlement, independently of native HUD formatting.
export function matchReferences(d,BattleSim,config,makeRng) {
  const template=new BattleSim(config),matchStatsInit=structuredClone(template.stats),matchDeaths=[];
  const actor=(id,side,hero=false,x=0)=>({id,pid:hero?String(id):null,hero,ch:hero?'t05':null,kind:hero?'robot':'soldier',side,
    x,z:0,y:0,hp:100,maxHp:100,money:10000,kn:0,mods:[],buffs:{},dead:false,deaths:0,abil:{light:1,heavy:1,def:1,atk:1}});
  for(const role of ['hero','creep','tower','base','third','hazard','civilian','carrier'])
    for(const killer of ['hero','npc','none','ally','third'])for(const distant of [false,true]) {
    const first=actor(1,'STEEL',true),target=actor(2,role==='third'?'GUER':'SWARM',role==='hero'),
      contributor=actor(3,'STEEL',true,distant?d.ECON.ASSIST.R_M+1:0);
    if(role==='tower'||role==='base')target.kind=role;
    if(role==='third')target.tp=1;
    if(role==='hazard')Object.assign(target,{kind:'fence',neutral:true});
    if(role==='civilian')Object.assign(target,{kind:'civilian',neutral:true,civ:true,cs:'SWARM',spy:false,noRespawn:true});
    if(role==='carrier')Object.assign(target,{kind:'hyper',hyper:true});
    const by=killer==='none'?null:killer==='hero'?first:actor(4,killer==='ally'?target.side:killer==='third'?'GUER':'STEEL',killer==='ally');
    target.hp=0;target.asst={'1':1,'3':1};
    const roster=[first,target,contributor,...(by&&by!==first?[by]:[])];
    const sim=Object.assign(Object.create(template),{t:10,_tickN:0,over:false,events:[],civRespawns:[],stats:structuredClone(matchStatsInit),
      ents:new Map(roster.map(e=>[e.id,e])),heroes:new Map(roster.filter(e=>e.hero).map(e=>[e.pid,e])),
      _deathPenalty:()=>{},_siegeFell:()=>{},_onThirdDeath:()=>{},_collapseScene:()=>{},_spawnLoot:()=>{},_hyperShotDown:()=>{},_removeHyper:()=>{}});
    const original=Math.random;Math.random=makeRng(42);
    try{sim._kill(target,by);}finally{Math.random=original;}
    matchDeaths.push({role,killer,distant,side:target.side,kind:target.kind,result:structuredClone(sim.stats)});
  }
  return {matchStatsInit,matchDeaths};
}
