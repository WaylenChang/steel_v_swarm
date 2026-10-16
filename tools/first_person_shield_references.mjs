// Original camera shield setup and update blocks; exported as native scenes, never runtime JS.
export function captureFirstPersonShields({THREE,d,BattleClient,fx,setupSource,graphOf,disposeTree,characterCombatStyle,characterShieldTexture}) {
  const setup=new Function(setupSource),graphs={},profiles={},geometry=[],frames=[],retargets=[];
  const updateSource=BattleClient.prototype._updateEnts.toString();
  const start=updateSource.indexOf('if (this._fpsShieldMesh) {'),end=updateSource.indexOf('for (const ent of this.ents.values()) {',start);
  if(start<0||end<=start)throw new Error('Missing original camera shield update block');
  const step=new Function('characterCombatStyle','characterShieldTexture','SHIELD_PRESENTATION_EXPAND','stepShieldMaterial','dt','now',updateSource.slice(start,end));
  const cast=/const defenseCast = ent\.castFx\?\.slot === 'def'[\s\S]*?if \(this\._fpsShieldMesh && defenseCast\) this\._fpsShieldMesh\.visible = this\.viewMode === 'fpv' && !this\.dead;/.exec(updateSource)?.[0];
  if(!cast)throw new Error('Missing original self defense-cast shield visibility gate');
  const castStep=new Function('ent','now',cast);
  const tick=(context,delta,now)=>step.call(context,characterCombatStyle,characterShieldTexture,fx.SHIELD_PRESENTATION_EXPAND,fx.stepShieldMaterial,delta,now);
  const state=context=>{
    const root=context._fpsShieldMesh,uniforms=root.userData.mat.uniforms;
    return {position:root.position.toArray(),quaternion:root.quaternion.toArray(),scale:root.scale.toArray(),visible:root.visible,
      character:root.userData.character,time:uniforms.uTime.value,flash:uniforms.uFlash.value,
      color:uniforms.uColor.value.toArray(),accent:uniforms.uAccent.value.toArray(),hasPattern:uniforms.uHasPattern.value};
  };
  const create=character=>{const context={ch:character,camera:new THREE.Group(),_createFrontShieldMesh:BattleClient.prototype._createFrontShieldMesh};setup.call(context);return context;};
  const previousRandom=Math.random;Math.random=()=>.25;
  try {
    for(const character of Object.keys(d.CHARACTERS)) {
      const context=create(character),root=context._fpsShieldMesh,graph=graphOf(root,true);
      graphs[character]=graph.data;profiles[character]={material:graph.materialOf(root.userData.mat)};
      geometry.push({character,nodes:graph.data.nodes,meshes:graph.data.meshes,materials:graph.data.materials,initial:state(context)});
      disposeTree(root);
      for(const mode of ['fpv','tps'])for(const defending of [false,true])for(const shield of [0,50])for(const dead of [false,true])for(const expanded of [0,10,10.000001]) {
        const sample=create(character);Object.assign(sample,{viewMode:mode,defending,sp:shield,dead,shieldExpandUntil:expanded});
        sample._fpsShieldMesh.userData.hit(1.8);
        const steps=[];
        for(const delta of [0,.016,.5,0]){tick(sample,delta,10);steps.push({delta,result:state(sample)});}
        for(const event of [null,{slot:'atk',t0:10},{slot:'def',t0:10},{slot:'def',t0:10.2}])for(const age of [0,.499999,.5,1]) {
          tick(sample,0,10+age);
          const ent={castFx:event,mesh:{userData:{rig:{combat:{clips:{def:{duration:.5}}}}}}};
          castStep.call(sample,ent,10+age);
          steps.push({delta:0,now:10+age,cast:event,duration:.5,result:state(sample)});
        }
        frames.push({character,mode,defending,shield,dead,expanded,steps});disposeTree(sample._fpsShieldMesh);
      }
    }
    const first=Object.keys(d.CHARACTERS)[0],sample=create(first);Object.assign(sample,{viewMode:'fpv',defending:true,sp:50,dead:false});
    sample._fpsShieldMesh.userData.hit(2.5);
    for(const character of [...Object.keys(d.CHARACTERS),'missing',first]) {
      sample.ch=character;tick(sample,.016,10);retargets.push({character,result:state(sample)});
    }
    disposeTree(sample._fpsShieldMesh);
  } finally {Math.random=previousRandom;}
  const snapSource=BattleClient.prototype._applySnap.toString();
  const ownStart=snapSource.indexOf('const vital = this.hp + this.sp;'),ownEnd=snapSource.indexOf('this._prevVital = vital;',ownStart);
  if(ownStart<0||ownEnd<=ownStart)throw new Error('Missing original private vital-loss/shield feedback gate');
  const feedback=new Function('ent','e','shieldHitStrength','performance',snapSource.slice(ownStart,ownEnd)),vitals=[];
  for(const fresh of [false,true])for(const hp of [99,100,101])for(const shield of [0,49,49.5,49.500001,50,60])for(const defending of [false,true])for(const dead of [false,true]) {
    let result={};const e={dead};
    const sample={hp,sp:shield,defending,_prevVital:fresh?null:150,_prevSp:fresh?null:50,
      _airSinkHit(){},hud:{hurt(){result={shielded:false,flash:0};}},_fpsShieldMesh:{userData:{hit:flash=>{result={shielded:true,flash};}}}};
    // The original block reads e.dead from the enclosing snapshot loop.
    feedback.call(sample,{shieldMesh:{userData:{hit(){}}}},e,fx.shieldHitStrength,{now:()=>10000});
    vitals.push({previous:fresh?{}:{hp:100,shield:50},current:{hp,shield,defending,dead},result});
  }
  return {graphs,profiles,fixtures:{firstPersonShieldGeometry:geometry,firstPersonShieldFrames:frames,firstPersonShieldRetargets:retargets,selfVitalHits:vitals}};
}
