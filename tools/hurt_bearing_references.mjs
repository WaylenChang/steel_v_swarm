// The source authority performs accumulation and publication rounding, including first-origin retention.
export function hurtBearingReferences(BattleSim) {
  const cases=[];
  for(const removed of [false,true]) {
    const heroes=new Map([3,1,2].map(id=>['p'+id,{id,pid:'p'+id,hero:true,dead:false}]));
    const context={heroes,events:[]},actions=[];
    for(const [target,attacker,x,z,amount,elevation]of [
      [2,8,-.05,.05,1.25,33.35],[1,9,12.55,-9.55,2.25,null],[2,8,200,300,2.25,900],
      [2,9,33.35,-33.35,.04,null],[1,9,1000,-1000,8.125,700],[3,8,12,-9,.001,0]]) {
      const origin=[Math.fround(x),0,Math.fround(z)],by={id:attacker,x:origin[0],z:-origin[2],hero:elevation!=null,
        ...(elevation!=null?{ay:elevation}:{})};
      BattleSim.prototype._hurtLog.call(context,heroes.get('p'+target),by,amount);
      actions.push({target,attacker,origin,amount,elevation});
    }
    if(removed)heroes.delete('p2');
    BattleSim.prototype._flushHurt.call(context);
    const events=context.events.map(event=>({actor:Number(event.tpid.slice(1)),origin:[event.x,0,-event.z],amount:event.v,
      ...(event.ay!=null?{elevation:event.ay}:{})}));
    context.events=[];BattleSim.prototype._flushHurt.call(context);
    cases.push({actions,order:[...heroes.values()].map(hero=>hero.id),events,repeated:context.events});
  }
  return {hurtBearingLog:cases};
}
