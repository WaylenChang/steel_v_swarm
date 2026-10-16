// Original renderer functions supply all geometry, style data, trajectories and fade references.
export function captureNpcShotReferences({THREE,d,BattleClient,fx,definitions,limits,setLowPower,graphOf,disposeTree}) {
  const styles=new Function(definitions+'\nreturn {byWid:UNIT_SHOT_STYLE,gun:UNIT_GUN,tower:UNIT_TOWER,base:UNIT_BASE};')();
  const colors=Object.fromEntries(['STEEL','SWARM','SUPER','GUER','MILI',''].map(side=>[side,BattleClient.prototype._shotCols(side)]));
  const graphs={},projectiles={},profiles={},geometry=[],projectileFx=[];
  const originalPower=localStorage.getItem('svs_lowpower');
  const scene=new THREE.Scene(),effects=[];
  const spriteContext=Object.create(BattleClient.prototype);
  spriteContext.scene=scene;spriteContext.effects=effects;spriteContext.terrain={heightAt:()=>20};
  spriteContext._applyBlast=()=>{};spriteContext._initFxPools();
  const clear=()=>{for(const effect of effects.splice(0))if(effect.obj)BattleClient.prototype._freeEffect.call({scene},effect);};
  const save=(key,object)=>{
    const mesh=new THREE.Mesh(object.geometry,object.material.clone());mesh.userData.noOutline=true;
    graphs[key]=graphOf(mesh,true).data;disposeTree(mesh);
  };
  setLowPower(false);
  fx.starburst(scene,effects,0,0,0,1);
  const sparkPng=effects[0].obj.material.map.image.toDataURL('image/png').split(',')[1];clear();
  fx.beamLine(scene,effects,new THREE.Vector3(),new THREE.Vector3(0,1,0),0xffffff);save('beam6',effects[0].obj);clear();
  fx.shockRing(scene,effects,0,0,0,1);save('shock',effects[0].obj);clear();
  fx.gundamBeam(scene,effects,new THREE.Vector3(),new THREE.Vector3(0,1,0),0xffffff,{r:1,rings:2});
  save('beam10',effects[0].obj);save('beam_ring',effects[2].obj);clear();
  fx.explosionBurst(scene,effects,0,0,0,1,0xffffff);save('bead',effects.at(-1).obj);clear();
  fx.ionBreath(scene,effects,new THREE.Vector3(),new THREE.Vector3(0,1,0),0xffffff);
  save('ion_throat',effects[0].obj);clear();
  const allColors=new Set([...Object.values(colors).map(value=>value.col),...Object.values(styles.byWid).flatMap(style=>style.color==null?[]:[style.color])]);
  for(const type of ['shell','rocket'])for(const color of allColors) {
    const key='npc-'+type+'-'+color.toString(16).padStart(6,'0');
    const mesh=fx.projectileMesh({type:type==='shell'?'gun':'missile'},{col:color,hue:color,heavy:true,compact:true});
    mesh.updateMatrixWorld(true);const graph=graphOf(mesh,true),anim=mesh.userData.projectileFx;
    projectiles[key]=graph.data;geometry.push({key,nodes:graph.data.nodes});
    profiles[key]={character:null,slot:'heavy',side:'',heavy:!!anim?.heavy,phase:anim?.phase||0,
      authored:(anim?.authored||[]).map(node=>graph.ids.get(node)),wake:graph.ids.get(anim?.wake)??-1,
      jets:(anim?.jets||[]).map(jet=>({node:graph.ids.get(jet.mesh),rad:jet.rad,len:jet.len,opacity:jet.opacity,nozzle:jet.nozzle}))};
    for(const age of [0,.017,.3,.65])for(const speed of [0,130,1000]) {
      fx.stepProjectileFx(mesh,age,speed);
      projectileFx.push({key,age,speed,nodes:[...graph.ids].filter(([node])=>node.isMesh).map(([node,id])=>
        ({id,position:node.position.toArray(),scale:node.scale.toArray(),opacity:node.material.opacity}))});
    }
    disposeTree(mesh);
  }
  const snapshot=(effect,type)=>{
    const object=effect.obj;
    const row={type,position:object.position.toArray(),quaternion:object.quaternion.toArray(),scale:object.scale.toArray(),visible:object.visible,
      opacity:object.material?.opacity??null,color:object.material?.color.getHex()??null,roll:object.isSprite?object.material.rotation:null};
    if(object.isInstancedMesh) {
      row.instances=Array.from({length:object.count},(_,index)=>{
        const matrix=new THREE.Matrix4();object.getMatrixAt(index,matrix);return matrix.toArray();});
      row.instanceColors=object.instanceColor?Array.from({length:object.count},(_,index)=>{
        const color=new THREE.Color();object.getColorAt(index,color);return color.toArray();}):[];
    }
    if(object.isGroup){const graph=graphOf(object,true);row.nodes=[...graph.ids].filter(([node])=>node.isMesh).map(([node,id])=>
      ({id,position:node.position.toArray(),scale:node.scale.toArray(),opacity:node.material.opacity}));}
    return row;
  };
  const cases=[],artillery=[],bursts=[];
  const origin=new THREE.Vector3(12,20,-9);
  for(const point of [[12,20,-9],[12,100,-9],[13,20,-9],[42,20,-9],[180,80,-100],[1000,-100,-500]])for(const mount of ['gun','turret','none']) {
    const to=new THREE.Vector3(...point),rig=mount==='gun'?{gunR:{comp:.55,aim:0}}:{},entity={mesh:{userData:{rig,...(mount==='turret'?{turret:{userData:{pitch:{}}}}:{})}}};
    const calls=[],context={_lobSolve:BattleClient.prototype._lobSolve,_lobVel:BattleClient.prototype._lobVel,_clipBeam:()=>{}};
    const arcSource=BattleClient.prototype._arcTracer.toString();
    const arc=new Function('BALLISTIC','UNITS','unitShotFx','performance','return function '+arcSource.trimStart().slice('_arcTracer'.length))(
      d.BALLISTIC,d.UNITS,(_scene,_effects,from,to,options)=>calls.push({velocity:options.velocity.toArray(),flight:options.flight,gravity:options.gravity}),{now:()=>10000});
    arc.call(context,origin,to,0xffffff,entity,'howitzer','siege');
    artillery.push({origin:origin.toArray(),target:point,mount,...calls[0],aim:rig.gunR?.aim??null,arc:entity._arcPitch??null});
  }
  const roster=['soldier','apc','tank','rocketeer','howitzer','heli','tower','base','robot','drone_wingman','assault_rover',
    'heli_squad','main_battle_tank','veteran_squad','carnival_heli'];
  const classify=effect=>effect.obj.isSprite?(effect.fade?.name==='_spriteGravFade'?'sprite_gravity':effect.fade?.name==='_spriteDriftFade'?'sprite_drift':'spark'):effect.obj.isInstancedMesh?(effect.obj.geometry.type==='SphereGeometry'?'debris':'rings'):effect.obj.isGroup?'projectile':
    effect.obj.geometry.type==='RingGeometry'?'shock':effect.obj.geometry.parameters.radialSegments===6?'beam':effect.obj.material.opacity===.42?'halo':'core';
  const previousRandom=Math.random;Math.random=()=>.25;
  const eventSource=BattleClient.prototype._onEvent.toString(),boomMarker="} else if (ev.e === 'boom') {";
  const boomStart=eventSource.indexOf(boomMarker),boomEnd=eventSource.indexOf("} else if (ev.e === 'decoyBomb') {",boomStart);
  if(boomStart<0||boomEnd<=boomStart)throw new Error('Missing original explosion event presentation seam');
  const boomEvent=new Function('shockRing','ev',eventSource.slice(boomStart+boomMarker.length,boomEnd));
  try {
    for(const low of [false,true])for(const kind of roster)for(const scenario of ['clear','wall','near','up','crowded','full']) {
      clear();setLowPower(low);
      const padding=['crowded','full'].includes(scenario)?(low?limits.low:limits.normal)-(scenario==='crowded'?1:0):0;
      effects.push(...Array.from({length:padding},()=>({obj:null})));
      const target=new THREE.Vector3(...(scenario==='near'?[12.005,20,-9]:scenario==='up'?[12,100,-9]:[120,25,-90]));
      const wall=scenario==='wall'?30:null,queries=[];
      const clip=(from,to)=>{
        const result=BattleClient.prototype._clipBeam.call({_obstHitT(ax,ay,az,bx,by,bz){
          if(wall==null||ax===bx)return null;const t=(wall-ax)/(bx-ax);return t>=0&&t<=1?t*Math.hypot(bx-ax,by-ay,bz-az):null;
        }},from,to);
        queries.push({from:from.toArray(),to:to.toArray(),result:{to:result.to.toArray(),cut:result.cut}});return result;
      };
      const options={kind,color:colors.STEEL.col,core:colors.STEEL.hot,clip},style=fx.unitShotStyle(kind);
      let motion=null;
      if(style.mode==='shell') {
        const solutions=[];
        new Function('BALLISTIC','UNITS','unitShotFx','performance','return function '+BattleClient.prototype._arcTracer.toString().trimStart().slice('_arcTracer'.length))(
          d.BALLISTIC,d.UNITS,(_scene,_effects,_from,_to,arc)=>solutions.push(arc),{now:()=>10000}).call(
            {_lobSolve:BattleClient.prototype._lobSolve,_lobVel:BattleClient.prototype._lobVel},origin,target,colors.STEEL.col,null,kind);
        motion={velocity:solutions[0].velocity.toArray(),gravity:solutions[0].gravity,flight:solutions[0].flight};Object.assign(options,solutions[0],{clip});
        delete options.core;
      }
      fx.unitShotFx(scene,effects,origin,target,options);
      const created=effects.slice(padding),types=created.map(classify),initial=created.map((effect,index)=>({ttl:effect.ttl,...snapshot(effect,types[index])}));
      const samples=[];
      for(const progress of [0,.1,.5,.999999,1,1.2]) {
        created.forEach(effect=>effect.fade?.(effect.obj,Math.max(0,1-progress),.016));
        samples.push({progress,effects:created.map((effect,index)=>snapshot(effect,types[index]))});
      }
      cases.push({kind,low,padding,origin:origin.toArray(),target:target.toArray(),wall,motion,queries,initial,samples});
    }
    for(const low of [false,true])for(const effect of ['muzzle','shot','impact','explosion'])
      for(const side of Object.keys(colors))for(const heavy of effect==='explosion'?[true]:[false,true])
        for(const scenario of ['clear','near','crowded','full']) {
      clear();setLowPower(low);
      const padding=['crowded','full'].includes(scenario)?(low?limits.low:limits.normal)-(scenario==='crowded'?1:0):0;
      effects.push(...Array.from({length:padding},()=>({obj:null})));
      const target=origin.clone().add(new THREE.Vector3(scenario === 'near' ? .005 : 108,0,0));
      const radius=scenario==='near'?0:1.6;
      const context={scene,effects,_shotCols:BattleClient.prototype._shotCols,_muzzleBurst:BattleClient.prototype._muzzleBurst};
      if(effect==='muzzle')BattleClient.prototype._muzzleBurst.call(context,origin,heavy,side);
      if(effect==='shot')BattleClient.prototype._shotFx.call(context,origin,target,{heavy,side,impact:heavy});
      if(effect==='impact')fx.impactBurst(scene,effects,origin,{r:radius,color:colors[side].col,core:colors[side].hot,heavy});
      if(effect==='explosion')fx.explosionBurst(scene,effects,origin.x,origin.y,origin.z,radius,colors[side].col);
      const created=effects.slice(padding),types=created.map(classify),initial=created.map((entry,index)=>({ttl:entry.ttl,...snapshot(entry,types[index])}));
      const samples=[];
      for(const progress of [0,.1,.5,.999999,1,1.2]) {
        created.forEach(entry=>entry.fade?.(entry.obj,Math.max(0,1-progress),.016));
        samples.push({progress,effects:created.map((entry,index)=>snapshot(entry,types[index]))});
      }
      bursts.push({effect,low,side,heavy,radius,padding,origin:origin.toArray(),target:target.toArray(),queries:[],initial,samples});
    }
    for(const low of [false,true])for(const height of [null,-1,0,2,11.999,12,80])
      for(const flavor of ['ordinary','sam','kami','both'])for(const scenario of ['clear','crowded','full']) {
      clear();setLowPower(low);
      const padding=scenario==='clear'?0:(low?limits.low:limits.normal)-(scenario==='crowded'?1:0);
      effects.push(...Array.from({length:padding},()=>({obj:null})));
      const ev={x:12,z:9,r:7,y:height,kami:flavor==='kami'||flavor==='both',sam:flavor==='sam'||flavor==='both'};
      boomEvent.call(spriteContext,fx.shockRing,ev);
      const created=effects.slice(padding),types=created.map(classify),initial=created.map((entry,index)=>({ttl:entry.ttl,...snapshot(entry,types[index])}));
      const samples=[];
      for(const progress of [0,.1,.5,.999999,1,1.2]) {
        created.forEach(entry=>entry.fade?.(entry.obj,Math.max(0,1-progress),.016));
        samples.push({progress,effects:created.map((entry,index)=>snapshot(entry,types[index]))});
      }
      bursts.push({effect:'boom',low,padding,ground:20,radius:ev.r,kami:ev.kami,sam:ev.sam,
        origin:[12,20+(height??2),-9],target:[12,20,-9],queries:[],initial,samples});
    }
  } finally {
    Math.random=previousRandom;clear();if(originalPower==null)localStorage.removeItem('svs_lowpower');else localStorage.setItem('svs_lowpower',originalPower);
    for(const key of ['_spritePoolFire','_spritePoolSmoke'])spriteContext[key].clear(node=>node.material.dispose());
    spriteContext._tracerPool.clear(node=>{node.geometry.dispose();node.material.dispose();});
    spriteContext._recPool.clear();spriteContext._fxShellPool.clear();
    spriteContext._fireTexC.dispose();spriteContext._smokeTexC.dispose();
  }
  const budgets=[];
  for(const count of [0,179,180,261,300])for(const delta of [0,.016,.5]) {
    const freed=[],fades=[],entries=Array.from({length:count},(_,id)=>({obj:{id},ttl:.1*(id%3+1),age:0,
      fade(object,f,dt){fades.push({id:object.id,f,delta:dt});}}));
    BattleClient.prototype._updateEffects.call({effects:entries,_freeEffect:effect=>freed.push(effect.obj.id)},delta);
    budgets.push({count,delta,freed,fades,remaining:entries.map(effect=>({id:effect.obj.id,ttl:effect.ttl,age:effect.age}))});
  }
  const styleCases=[];
  for(const kind of [...Object.keys(d.UNITS),'unknown'])for(const wid of [null,'',...Object.keys(styles.byWid),'unknown'])
    styleCases.push({kind,wid,result:fx.unitShotStyle(kind,wid)});
  const reportSource=/const wid = ev\.wid \|\| \(ent \? UNITS\[ent\.kind\]\?\.wid : null\);[\s\S]*?const style = unitShotStyle\(kind, wid\);/.exec(eventSource)?.[0];
  if(!reportSource)throw new Error('Missing original NPC shot report override/fallback ordering');
  const report=new Function('ev','ent','UNITS','unitShotStyle',reportSource+'return {kind:kind??"",wid:wid??null,style};');
  const reports=[];
  for(const actor of [...Object.keys(d.UNITS),'unknown',''])for(const kind of [null,'','howitzer','base'])for(const wid of [null,'','wingman_beam']) {
    const event={kind,wid};reports.push({actor,event,result:report(event,actor?{kind:actor}:null,d.UNITS,fx.unitShotStyle)});
  }
  return {graphs,projectiles,profiles,geometry,projectileFx,sparkPng,
    rules:{...styles,colors,limits,clipBack:Number(/\(d - ([\d.]+)\)/.exec(BattleClient.prototype._clipBeam.toString())[1]),
      arcHold:Number(/until: performance\.now\(\) \/ 1000 \+ ([\d.]+)/.exec(BattleClient.prototype._arcTracer.toString())[1])},
    fixtures:{npcShotEffects:cases,combatBursts:bursts,npcArtillery:artillery,npcEffectBudget:budgets,npcShotStyles:styleCases,npcShotReports:reports}};
}
