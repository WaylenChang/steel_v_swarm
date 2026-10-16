// Runs only inside the final source-browser import; every mount query uses the original methods.
export function captureNpcBodyReferences({key,kind,dimensions,create,graphOf,snapshot,BattleClient,fireUnitMotion,unitShotStyle,disposeTree}) {
  const model=create(),graph=graphOf(model),before=new Map();snapshot(graph,before,true);
  const entity={id:'npc/'+key,kind,dimH:dimensions.height,mesh:model,guns:model.userData.baseGuns,
    gunPivots:model.userData.baseGuns?.userData.pivots,gunMuzzles:model.userData.baseGuns?.userData.muzzles},client={_nearestEnemy:()=>null},steps=[];
  const inputs=[{now:10,delta:0,yaw:0,nearest:[20,30,-40]},
    {now:10,delta:-.1,yaw:0,nearest:[20,30,-40]},
    {now:10.02,delta:.02,yaw:.7,nearest:[20,30,-40]},
    {now:10.12,delta:.1,yaw:3.12,nearest:[-30,-100,20]},
    {now:10.3,delta:.18,yaw:-3.12,aim:{x:12,y:200,z:-9,until:10.4},nearest:[40,0,80],batteryYaw:.7,
      guns:[{x:-20,y:100,z:10,until:10.4},{x:60,y:-40,z:20,until:10.5}]},
    {now:10.4,delta:.1,yaw:-3.12,nearest:null},
    {now:10.5,delta:.1,yaw:0,arc:{v:4,until:11},nearest:[100,0,0]},
    {now:10.6,delta:.1,yaw:0,arc:{v:-4,until:11},nearest:null,batteryYaw:-3.12,
      guns:[{x:-20,y:-100,z:10,until:11},null]},
    {now:10.7,delta:.1,yaw:0,arc:{v:0,until:11},nearest:[0,100,0]},
    {now:11,delta:.3,yaw:0,nearest:null}];
  for(const input of inputs) {
    model.position.set(12,20,-9);model.rotation.y=input.yaw;
    if(input.aim)entity._aimAt={...input.aim};if(input.arc)entity._arcPitch={...input.arc};
    if(input.guns)entity._gunAim=input.guns.map(aim=>aim?{...aim}:null);
    if(input.batteryYaw!=null&&entity.guns)entity.guns.rotation.y=input.batteryYaw;
    const point=input.nearest?new model.position.constructor(...input.nearest):null;
    client._nearestEnemy=()=>point?{mesh:{position:point}}:null;
    if(model.userData.turret) {
      if(kind==='tower')BattleClient.prototype._aimTurret.call(client,entity,input.delta,input.now);
      else BattleClient.prototype._aimVehicleTurret.call(client,entity,model.userData.turret,input.delta,input.now);
    }
    if(model.userData.gunTilt)BattleClient.prototype._aimGunTilt.call(client,entity,model.userData.gunTilt,input.delta,input.now);
    if(entity.guns)BattleClient.prototype._aimBaseGuns.call(client,entity,input.delta,input.now);
    model.updateMatrixWorld(true);
    steps.push({...input,nodes:snapshot(graph,before,true)});
  }
  const shots=[];
  for(const [index,now]of [12,12,12.1].entries()) {
    const event={to:[30,-40],gi:kind==='base'?index%2:0},client={terrain:{heightAt:()=>20}};
    const origin=BattleClient.prototype._npcMuzzle.call(client,entity,event,12,-9);
    const style=unitShotStyle(kind),slot=style.mode==='gun'||style.mode==='beam'?'light':'heavy';
    entity.fireFx={t0:now,slot};
    const muzzle=kind==='base'?entity.gunMuzzles?.[event.gi]:model.userData.turretMuzzles?.[entity._mzi]||model.userData.rig?.muzzles?.light?.n;
    fireUnitMotion(model.userData.rig,muzzle,now);
    shots.push({index,now,slot,gun:event.gi,origin:origin.toArray(),muzzle:graph.ids.get(muzzle)??null,
      firedAt:(model.userData.rig.attacks||[]).map(attack=>Number.isFinite(attack.firedAt)?attack.firedAt:null),
      muzzleIndex:entity._mzi??null});
  }
  const fallback=[];
  model.visible=false;
  for(const garrison of [false,true])for(const override of [null,0,30])for(const point of [[12,24,-9],[30,24,40]]) {
    entity.gar=garrison;
    const event={to:[point[0],-point[2]],...(override==null?{}:{oy:override})};
    const origin=BattleClient.prototype._npcMuzzle.call({terrain:{heightAt:()=>10}},entity,event,12,-9);
    fallback.push({position:model.position.toArray(),ground:10,height:entity.dimH,target:point,garrison,override,result:origin.toArray()});
  }
  model.visible=true;
  const nearest=[];
  for(const structures of [false,true]) {
    const caster={mesh:model,side:'STEEL'},rows=[
      {id:1,side:'STEEL',position:[13,20,-9]}, {id:2,side:'',position:[13,20,-9]},
      {id:3,neutral:true,position:[13,20,-9]}, {id:4,dead:true,position:[13,20,-9]},
      {id:5,visible:false,position:[13,20,-9]}, {id:6,static:true,position:[14,20,-9]},
      {id:7,self:true,visible:false,position:[15,20,-9]}, {id:8,position:[16,20,-9]},
      {id:9,position:[16,50,-9]}, {id:10,position:[32,20,-9]}]
      .map(row=>({side:'SWARM',neutral:false,dead:false,static:false,visible:true,self:false,...row}));
    const entries=new Map(rows.map(row=>[row.id,{id:row.id,side:row.side,neutral:row.neutral,dead:row.dead,isStatic:row.static,
      isSelf:row.self,mesh:{visible:row.visible,position:new model.position.constructor(...row.position)}}]));
    const client={ents:entries},sequence=[];
    for(const [index,now]of [20,20.1,20.249999,20.25,20.5].entries()) {
      const cached=caster._aimTarget;
      if(index===1&&cached){cached.dead=true;cached.mesh.visible=false;}
      if(index===2&&cached)entries.delete(cached.id);
      const result=BattleClient.prototype._nearestEnemy.call(client,caster,now,20,structures);
      sequence.push({now,result:result?.id??0,next:caster._aimNext,cached:caster._aimTarget?.id??0,
        candidates:[...entries.values()].map(target=>({id:target.id,side:target.side,neutral:target.neutral,dead:target.dead,
          static:target.isStatic,self:target.isSelf,visible:target.mesh.visible,position:target.mesh.position.toArray()}))});
    }
    nearest.push({side:caster.side,position:model.position.toArray(),reach:20,structures,steps:sequence});
  }
  const modelKey=model.userData.kind;
  disposeTree(model);return {key,kind,modelKey,steps,shots,fallback,nearest};
}

// Clones have an entity id but no player id in the original _tickClones shot report.
export function captureCloneBodyReferences({key,kind,dimensions,create,graphOf,snapshot,BattleClient,fireUnitMotion,unitShotStyle,stepCombatFx,disposeTree,d}) {
  const source=BattleClient.prototype._onEvent.toString(),shot=source.indexOf("ev.e === 'shot'");
  const start=source.indexOf('        const ent = ev.id != null ? this.ents.get(ev.id) : null;',shot);
  const end=source.indexOf('        const { col, hot } = this._shotCols(ev.side);',start);
  if(shot<0||start<shot||end<start)throw new Error('Missing original entity-only clone shot presentation');
  const onShot=new Function('ev','fx','fz','tx','tz','to','t0','UNITS','unitShotStyle','fireUnitMotion',
    source.slice(start,end)+'return from;');
  const actors=['owner','clone','sibling'].map((id,index)=>{
    const mesh=create(),graph=graphOf(mesh),before=new Map();snapshot(graph,before,true);
    mesh.position.set(12+index*4,20,-9);mesh.updateMatrixWorld(true);
    return {id,mesh,graph,before,kind,pid:1,hero:true,dimH:dimensions.height};
  });
  const client={ents:new Map(actors.map(actor=>[actor.id,actor])),terrain:{heightAt:()=>20},
    _npcMuzzle:BattleClient.prototype._npcMuzzle};
  const steps=[],inputs=[{serial:1,now:10},{serial:1,now:10,reject:true},
    {serial:2,now:10,step:.016},{serial:3,now:10.1,step:.1},
    {serial:4,now:10.2},{serial:5,now:10.2,step:.1}];
  for(const input of inputs) {
    let origin=null;
    if(!input.reject) {
      const ev={e:'shot',id:'clone',kind,from:[16,9],to:[30,-40],ty:2,side:'STEEL'};
      origin=onShot.call(client,ev,16,-9,30,40,new actors[1].mesh.position.constructor(30,24,40),input.now,
        d.UNITS,unitShotStyle,fireUnitMotion).toArray();
    }
    if(input.step)for(const actor of actors)stepCombatFx(actor,input.now,input.step);
    steps.push({...input,origin,actors:actors.map(actor=>{
      actor.mesh.updateMatrixWorld(true);
      const forms=actor.mesh.userData.morph?{ground:actor.mesh.userData.morph.ground,air:actor.mesh.userData.morph.air}:{ground:actor.mesh.userData.rig};
      return {id:actor.id,fire:actor.fireFx??null,aim:actor._aimAt??null,
        forms:Object.fromEntries(Object.entries(forms).map(([form,rig])=>[form,{
          indices:Object.fromEntries(Object.entries(rig.weaponSequences||{}).map(([slot,sequence])=>[slot,sequence.index])),
          times:Object.fromEntries(Object.entries(rig.weaponSequences||{}).map(([slot,sequence])=>[slot,
            sequence.entries.map(entry=>Number.isFinite(entry.firedAt)?entry.firedAt:null)]))
        }])),nodes:snapshot(actor.graph,actor.before,true)};
    })});
  }
  actors.forEach(actor=>disposeTree(actor.mesh));
  return {key,steps};
}
