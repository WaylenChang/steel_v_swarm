// Offline execution of original sprite pools, producers and the actual global effect tick.
export function captureSpriteReferences({THREE,BattleClient,limits,fx}) {
  const context=Object.create(BattleClient.prototype);
  context.scene=new THREE.Scene();context.effects=[];
  context._initFxPools();
  const textures={fire:context._fireTex().image.toDataURL('image/png').split(',')[1],
    smoke:context._smokeTex().image.toDataURL('image/png').split(',')[1]};
  const free=BattleClient.prototype._freeEffect;
  context._freeEffect=function(effect){if(effect.obj)free.call(this,effect);};
  const clear=()=>{for(const effect of context.effects.splice(0))context._freeEffect(effect);};
  const pools=()=>({fire:context._spritePoolFire.size,smoke:context._spritePoolSmoke.size});
  const snapshot=()=>context.effects.filter(effect=>effect.obj).map(effect=>{
    const node=effect.obj,u=node.userData;
    return {type:effect.fade.name==='_spriteGravFade'?'sprite_gravity':'sprite_drift',fire:u.fire,
      position:node.position.toArray(),scale:node.scale.toArray(),quaternion:node.quaternion.toArray(),visible:node.visible,
      opacity:node.material.opacity,color:node.material.color.getHex(),velocity:u.vel.toArray(),
      ttl:effect.ttl,age:effect.age,delay:u.delay};
  });
  const previousRandom=Math.random,cases=[];
  try {
    for(const method of ['embers','smoke','plume','engulf'])for(const variant of [0,1,8,103,300])for(const padding of [0,limits.maximum-1]) {
      if(method==='engulf'?variant>8:method!=='embers'&&variant!==1)continue;
      clear();
      let draws=0;const random=[.25,0,.999999,.5,.125,.875,.375,.625];
      Math.random=()=>random[(draws++)%random.length];
      context.effects.push(...Array.from({length:padding},()=>({obj:null,ttl:100,age:0})));
      const point=new THREE.Vector3(12,20,-9);
      const camera=new THREE.PerspectiveCamera();camera.position.copy(point);
      camera.rotation.set(.17*variant,-.6*variant,.08*variant,'YXZ');camera.updateMatrixWorld(true);
      if(method==='embers')context._emberBurst(point.x,point.y,point.z,variant,2);
      else if(method==='smoke')context._crashSmoke(point.x,point.y,point.z,1.4);
      else if(method==='plume')context._deathPlume(point.x,point.y,point.z);
      else context._engulfFPV(camera);
      const initial=snapshot(),initialPools=pools(),steps=[];
      for(const delta of [0,.016,.08,.4,.016,.7,1.1]) {
        context._updateEffects(delta);
        steps.push({delta,effects:snapshot(),pools:pools(),count:context.effects.length});
      }
      cases.push({method,variant,padding,point:point.toArray(),camera:camera.matrixWorld.toArray(),random,draws,initial,initialPools,steps});
    }
  } finally {
    Math.random=previousRandom;clear();
    for(const key of ['_spritePoolFire','_spritePoolSmoke'])context[key].clear(node=>node.material.dispose());
    context._tracerPool.clear(node=>{node.geometry.dispose();node.material.dispose();});
    context._recPool.clear();context._fxShellPool.clear();
    context._fireTexC.dispose();context._smokeTexC.dispose();
  }
  const snapSource=BattleClient.prototype._applySnap.toString();
  const ordinary=/if \(e\.hp < prevHpSnap && !HERO_KINDS\.has\(e\.k\)\) this\._victimHitFx\(ent, false\);/.exec(snapSource)?.[0];
  const shieldStart=snapSource.indexOf('const _spDrop ='),shieldEnd=snapSource.indexOf('ent.sp = e.sp',shieldStart);
  if(!ordinary||shieldStart<0||shieldEnd<=shieldStart)throw new Error('Missing original snapshot victim-hit gates');
  const gates=new Function('HERO_KINDS','shieldHitStrength','ent','e','const prevHpSnap=ent.hp;\n'+ordinary+
    '\nif(HERO_KINDS.has(e.k)){'+snapSource.slice(shieldStart,shieldEnd)+'}');
  const gateCases=[];
  for(const hero of [false,true])for(const fresh of [false,true])for(const hp of [120,100,99,0])for(const shield of [60,50,49,0])for(const defending of [false,true]) {
    let result={};
    const e={k:hero?'robot':'soldier',hp,sp:shield,df:defending},ent={hp:fresh?hp:100,sp:fresh?shield:50,
      shieldMesh:{userData:{hit:flash=>{result.flash=flash;}}}};
    gates.call({_victimHitFx(_entity,shielded){result.shielded=shielded;if(!shielded)result.flash=0;}},
      new Set(['drone','robot','morph']),fx.shieldHitStrength,ent,e);
    gateCases.push({hero,previous:fresh?{}:{hp:100,shield:50},current:{hp,shield,defending},result});
  }
  const victimCases=[];
  let calls=[];
  const point=value=>value.toArray();
  const victim=new Function('starburst','shockRing','return function '+BattleClient.prototype._victimHitFx.toString().slice('_victimHitFx'.length))(
    (_scene,_effects,x,y,z,radius,color)=>calls.push({type:'spark',point:[x,y,z],radius,color}),
    (_scene,_effects,x,y,z,radius,color)=>calls.push({type:'shock',point:[x,y,z],radius,color}));
  for(const kind of ['robot','soldier','tower','base','car','rockfall'])for(const height of [0,4,32])for(const distance of [null,0,59.999,60,120,240,500])for(const shielded of [false,true]) {
    calls=[];const origin=new THREE.Vector3(12,20,-9),camera=distance==null?null:origin.clone().add(new THREE.Vector3(distance,0,0));
    const view={camera:camera?{position:camera}:null,_hitFxScale:BattleClient.prototype._hitFxScale,
      _emberBurst(x,y,z,count,spread){calls.push({type:'embers',point:[x,y,z],count,spread});},
      _crashSmoke(x,y,z,size){calls.push({type:'smoke',point:[x,y,z],size});}};
    victim.call(view,{kind,mesh:{position:origin},dimH:height},shielded);
    victimCases.push({kind,height,origin:point(origin),camera:camera?point(camera):null,shielded,calls});
  }
  return {textures,fixtures:{combatSprites:cases,victimHitGates:gateCases,victimHitPrimitives:victimCases}};
}
