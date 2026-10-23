// Execute current heroCast routing rather than inferring active mechanics from dormant methods.
export function abilityRouteReferences(d, BattleSim) {
  const fixtures=[];
  for(const character of Object.keys(d.CHARACTERS)) for(const slot of ['def','atk']) {
    const samples=[...Array.from({length:d.ECON.UPGRADES[slot].max+1},(_,index)=>({level:index+1})),
      ...Array.from({length:d.SUPER_UPG.MAX+1},(_,superLevel)=>({superLevel,level:d.superCombatLvl(superLevel)}))];
    for(const sample of samples) {
      const definition=d.heroAbility(character,slot,sample.level);
      if(definition.support) throw new Error('Current source has reintroduced support fleets; implement their production path before enabling this content');
      const actor={id:1,pid:'1',hero:true,ch:character,kind:d.CHARACTERS[character].kind,side:'STEEL',
        x:40,z:-50,y:12,ry:.7,hp:100,mp:100000,dead:false,defending:true,
        abil:{def:sample.level,atk:sample.level},acd:{},achg:{},mods:[],buffs:{}};
      const calls=[];
      const simulation=Object.assign(Object.create(BattleSim.prototype),{t:10,over:false,heroes:new Map([[actor.pid,actor]]),
        events:[],curWeatherDyn:null,_readyCharges:()=>1,_jammed:()=>false,
        _launchOrigin:()=>({x:-100,z:200,y:0}),
        _launchAtkCarrier:(_h,_A,x,z)=>calls.push({route:'carrier',x,z}),
        _castEffect:(_h,_A,x,z)=>calls.push({route:'hull',x,z})});
      simulation.heroCast(actor.pid,slot,120,-70);
      const route=actor.cast?'channel':calls[0]?.route;
      if(!route||calls.length>1) throw new Error('Original ability did not take exactly one active route');
      const point=actor.cast?{x:actor.cast.x,z:actor.cast.z}:calls[0];
      fixtures.push({character,slot,...sample,definition:{fx:definition.fx,carrier:definition.carrier,support:definition.support,
        target:definition.target??null,added:definition.add?.fx??null,unit:definition.unit??null},
        route,point:[point.x,0,-point.z],eventPoint:simulation.events.at(-1)?[simulation.events.at(-1).x,0,-simulation.events.at(-1).z]:null});
    }
  }
  return {abilityRoutes:fixtures};
}
