// Original report dispatch, burst callbacks and muzzle selection; no renderer or combat simulation runs here.
export function captureRemoteShotReferences({THREE,d,BattleClient}) {
  let clock=10;
  const scope={THREE,aoeClass:d.aoeClass,altRangeMax:d.altRangeMax,RANGE_TOL:d.RANGE_TOL,
    fireBurstN:d.fireBurstN,fireBurstGap:d.fireBurstGap,performance:{now:()=>clock*1000}};
  const method=name=>new Function(...Object.keys(scope),'return function '+BattleClient.prototype[name].toString().slice(name.length))(...Object.values(scope));
  const tracer=method('onTracer'),botShot=method('_onEvent'),burst=method('_burstEchoOther'),queue=method('_queueBurst'),tick=method('_tickBurstFx');
  const cases=[];
  for(const character of Object.keys(d.CHARACTERS))for(const slot of ['light','heavy'])for(const bot of [false,true]) {
    const definition=d.heroWeapon(character,slot,1);
    if(d.aoeClass(definition)==='fan')continue;
    for(const scenario of ['clear','hit','wall','out','near','zero','removed','absent','absent_hit','absent_wall']) {
      clock=10;
      const origin=new THREE.Vector3(12,20,-9),live=origin.clone(),target=origin.clone().add(new THREE.Vector3(0,0,
        scenario === 'zero' ? 0 : scenario === 'near' ? .05 : scenario === 'out' ? definition.range*d.altRangeMax(definition)*d.RANGE_TOL+100 : 120));
      let present=!scenario.startsWith('absent');
      const shots=[],marks=[],queries=[];
      const context={ents:new Map(),terrain:{heightAt:()=>20},_heroEntByPid:()=>present?{ch:character}:null,
        _heroDefOf:(ch,s)=>d.heroWeapon(ch,s,1),_entMuzzle:(_pid,_slot,fallback)=>present?live.clone():fallback,
        _clipBeam(from,to){
          const clipped=BattleClient.prototype._clipBeam.call({_obstHitT(ax,ay,az,bx,by,bz){
            if(!['wall','absent_wall'].includes(scenario)||az===bz)return null;
            const t=(30-az)/(bz-az);return t>=0&&t<=1?t*Math.hypot(bx-ax,by-ay,bz-az):null;
          }},from,to);
          queries.push({from:from.toArray(),to:to.toArray(),result:{to:clipped.to.toArray(),cut:clipped.cut}});return clipped;
        },
        _lanceVisual(_from,to){shots.push({kind:'lance',target:to.toArray()});},
        _spawnVisShell(_from,to){shots.push({kind:'shell',target:to.toArray()});return new THREE.Vector3(0,.4,1).normalize();},
        _shotFx(_from,to,options){shots.push({kind:'shot',target:to.toArray(),impact:options.impact});},
        _muzzleBurst(){},_aimHeavyBarrel(){},_markFire(pid,s,_time,aim){marks.push({pid,slot:s,aim});},
        _burstEchoOther:burst,_queueBurst:queue};
      if(bot)botShot.call(context,{e:'shot',pid:2,slot,side:'STEEL',from:[origin.x,-origin.z],to:[target.x,-target.z],ty:target.y-22});
      else tracer.call(context,{pid:2,slot,side:'STEEL',from:origin.toArray(),to:target.toArray(),hit:scenario.endsWith('hit')});
      const initial={plan:shots.shift(),marks:marks.splice(0),queries:queries.splice(0),
        pending:(context._burstQ||[]).map(item=>({at:item.at,index:item.i,count:item.n}))};
      const steps=[];
      for(const now of [10,10.000001,10.1,10.25,11,11]) {
        clock=now;live.x+=.5;
        if(scenario==='removed'&&now>10)present=false;
        tick.call(context,now);
        steps.push({now,origin:present?live.toArray():target.toArray(),shots:shots.splice(0),marks:marks.splice(0),queries:queries.splice(0),
          pending:(context._burstQ||[]).map(item=>({at:item.at,index:item.i,count:item.n}))});
      }
      const reportOrigin=origin.toArray();if(bot&&scenario.startsWith('absent'))reportOrigin[1]=22;
      cases.push({character,slot,bot,scenario,origin:reportOrigin,target:target.toArray(),hit:scenario.endsWith('hit'),initial,steps});
    }
  }
  const muzzleCases=[];
  for(const hidden of [false,true])for(const fallback of [[0,0,0],[12,20,-9],[100,0,0]])for(const slot of ['light','heavy']) {
    const records=[{id:1,pid:2,position:[1,0,0],port:[2,1,0]},
      {id:2,pid:2,position:[-1,0,0],port:[-2,1,0]},
      {id:3,pid:3,position:[0,0,0],port:[0,1,0]},
      {id:4,pid:2,self:true,position:[0,0,0],port:[0,2,0]},
      {id:5,pid:2,fx:true,position:[0,0,0],port:[0,3,0]},
      {id:6,pid:2,missing:true,position:[0,0,0],port:[0,4,0]}];
    const entities=records.map(record=>{
      const mesh=new THREE.Group();mesh.position.fromArray(record.position);mesh.visible=!hidden;
      const node=new THREE.Object3D();node.position.fromArray(record.port);mesh.add(node);mesh.updateMatrixWorld(true);
      mesh.userData.rig={muzzles:{[slot]:{n:record.missing?null:node,fxOnly:record.fx}}};
      return {id:record.id,pid:record.pid,isSelf:record.self,mesh,node,record};
    });
    const point=BattleClient.prototype._entMuzzle.call({ents:new Map(entities.map(ent=>[ent.id,ent]))},2,slot,new THREE.Vector3(...fallback));
    muzzleCases.push({fallback,slot,result:point.toArray(),candidates:entities.filter(ent=>ent.pid===2).map(ent=>({position:ent.mesh.position.toArray(),
      muzzle:ent.record.missing?null:ent.node.getWorldPosition(new THREE.Vector3()).toArray(),self:!!ent.isSelf,fx_only:!!ent.record.fx}))});
  }
  const barrel=[];
  for(const hand of ['L','R','none']) {
    const rig={weap:{heavy:hand},...(hand==='none'?{}:{gunL:{aim:.7},gunR:{aim:1.1}})},entity={pid:2,mesh:{userData:{rig}}},steps=[];
    for(const vector of [[0,1,0],[0,0,0],[.2,-.3,.9],[0,-1,0]]) {
      BattleClient.prototype._aimHeavyBarrel.call({ents:new Map([[1,entity]])},2,new THREE.Vector3(...vector));
      steps.push({direction:vector,gunL:rig.gunL?{...rig.gunL}:null,gunR:rig.gunR?{...rig.gunR}:null});
    }
    barrel.push({hand,steps});
  }
  const source=BattleClient.prototype._tryFire.toString().replace(/\r\n?/g,'\n'),start=source.indexOf('    const to = lobFc\n'),end=source.indexOf('\n    });',start);
  if(start<0||end<start)throw new Error('Missing original physical launch relay seam');
  const relay=new Function('muzzle','dir','lobFc','id',source.slice(start,end+'\n    });'.length));
  const relays=[];
  for(const direction of [[0,0,-1],[.2,.4,.8],[0,0,0]])for(const speed of [null,50.499999,50.5,100.999]) {
    const origin=[12,20,-9],aim=[40,3,-100],reports=[];
    relay.call({net:{send:report=>reports.push(report)}},new THREE.Vector3(...origin),new THREE.Vector3(...direction),
      speed==null?null:{aim:new THREE.Vector3(...aim),v0:speed},'heavy');
    relays.push({origin,direction,arc:speed==null?null:{aim,speed},result:{target:reports[0].to,speed:reports[0].mv??null}});
  }
  return {remoteShotReports:cases,remoteMuzzleSelection:muzzleCases,remoteBarrelAim:barrel,remoteLaunchRelay:relays};
}
