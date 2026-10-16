// Run the original removal and shared effect methods; do not reconstruct their curves.
export function captureBodyRemoval({THREE,d,sceneDamage,BattleClient,mapBuilding,disposeTree,limits}) {
  let bursts=[],disposed=false;
  const remove=new Function('releaseLightningScorch','releaseMobileDamage','sceneDamageBurst','sceneDamageProfile','applySceneDamage',
    'MAP_BUILDING','DISSOLVE','setDissolve','disposeTree','return function '+BattleClient.prototype._removeEnt.toString())(
      ()=>{},entity=>{entity.released=true;},(_scene,_effects,entity,stage)=>bursts.push({id:entity.id,stage}),
      sceneDamage.sceneDamageProfile,(entity,stage)=>{entity.sceneStage=stage;},mapBuilding.MAP_BUILDING,d.DISSOLVE,()=>0,()=>{disposed=true;});
  const update=new Function('FX_MAX','return function '+BattleClient.prototype._updateEffects.toString())(limits.maximum);
  const bodyRemoval=[];
  let rules=null;
  const snapshot=BattleClient.prototype._applySnap.toString();
  const removalAt=snapshot.indexOf('this._removeEnt(id, ent, deadIds.has(id))');
  const eventsAt=snapshot.indexOf('for (const ev of m.ev || []) this._onEvent(ev);');
  if(removalAt<0||eventsAt<=removalAt)throw new Error('Original body removal must precede world event playback');
  for(const kind of ['robot','soldier','tower','base','bunker','mapbuilding','slab'])
    for(const dissolve of [false,true])for(const visible of [false,true])for(const evict of [false,true]) {
      bursts=[];disposed=false;
      const scene=new THREE.Scene(),mesh=new THREE.Mesh(new THREE.BoxGeometry(2,6,2),new THREE.MeshStandardMaterial());
      const scale=[1.2,1.7,.9];mesh.scale.fromArray(scale);mesh.rotation.set(.13,.21,-.17);mesh.position.set(12,20,-9);mesh.visible=visible;scene.add(mesh);
      const ent={id:42,kind,mesh,neutral:false,dmgFx:new THREE.Group()};mesh.add(ent.dmgFx);
      const client={scene,effects:[],ents:new Map([[42,ent]]),damaged:new Set([ent]),spinners:new Map(),flamers:new Map(),
        _dissolveGhosts:[],_unregisterViewOccluders(){},_freeEffect:BattleClient.prototype._freeEffect};
      const capture=()=>({attached:mesh.parent===scene,visible:mesh.visible,scale:mesh.scale.toArray(),effects:client.effects.length,
        stage:ent.sceneStage??-1,fxVisible:ent.dmgFx.visible,disposed,bursts:bursts.slice()});
      remove.call(client,42,ent,dissolve);
      if(dissolve) {
        const effect=client.effects[0],mobile=!!sceneDamage.sceneDamageProfile(kind).mobile;
        effect.fade(mesh,0);const floor=mesh.scale.y/scale[1];effect.fade(mesh,1);
        rules??={duration:effect.ttl};rules[mobile?'mobileFloor':'staticFloor']=floor;
        for(const f of [.25,.5,.75]) {
          effect.fade(mesh,f);const expected=floor+(1-floor)*(mobile?f:f*f);
          if(Math.abs(mesh.scale.y/scale[1]-expected)>1e-12)throw new Error('Original body removal curve changed');
        }
        effect.fade(mesh,1);
      }
      const initial=capture(),frames=[];
      for(const [index,delta]of [0,.016,0,.12,.2,.1,.3,.09,.1].entries()) {
        if(evict&&index===1)client.effects.push(...Array.from({length:limits.maximum},()=>({obj:new THREE.Group(),ttl:100,age:0})));
        update.call(client,delta);frames.push({delta,...capture()});
      }
      bodyRemoval.push({kind,dissolve,visible,evict,scale,initial,frames});
      for(const effect of client.effects)client._freeEffect(effect);
      disposeTree(mesh);
    }
  if(!rules||!Number.isFinite(rules.staticFloor)||!Number.isFinite(rules.mobileFloor))throw new Error('Missing original removal curves');
  rules.beforeWorldEvents=true;
  return {rules,fixtures:{bodyRemoval}};
}
