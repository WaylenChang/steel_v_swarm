// Capture original pooled comic sprites and instanced mechanical debris offline.
export function captureDestruction({THREE,d,sceneDamage,fx,BattleClient,setLowPower,graphOf,disposeTree,limits}) {
  const previous=Math.random,stored=localStorage.getItem('svs_lowpower');
  const random=[.125,.875,.375,.625,0,.999,.25,.75,.5],graphs={},textures={},textureKeys=new Map(),debris=[],comics=[];
  const scene=new THREE.Scene(),effects=[];
  const release=()=>{for(const effect of effects.splice(0))BattleClient.prototype._freeEffect.call({scene},effect);};
  const batches=object=>object.children.map(batch=>({
    matrices:Array.from({length:batch.count},(_,index)=>{const m=new THREE.Matrix4();batch.getMatrixAt(index,m);return m.toArray();}),
    colors:Array.from({length:batch.count},(_,index)=>{const c=new THREE.Color();batch.getColorAt(index,c);return c.toArray();})}));
  const states=()=>effects.filter(effect=>effect.obj).map(effect=>({ttl:effect.ttl,age:effect.age??0,
    batches:effect.obj.isGroup?batches(effect.obj):null,position:effect.obj.position.toArray(),scale:effect.obj.scale.toArray(),
    opacity:effect.obj.material?.opacity??null,roll:effect.obj.material?.rotation??null,
    texture:effect.obj.isSprite?textureKeys.get(effect.obj.material.map):null,
    color:effect.obj.material?.color?.toArray()??null}));
  let palette=[];
  try {
    setLowPower(false);
    fx.debrisBurst(scene,effects,0,0,0,{random:()=>.5});
    for(const [index,batch]of effects[0].obj.children.entries()) {
      const mesh=new THREE.Mesh(batch.geometry,batch.material.clone());
      graphs['chunk'+index]=graphOf(mesh,true).data;
      const color=new THREE.Color();batch.getColorAt(0,color);palette.push(color.getHex());
      disposeTree(mesh);
    }
    release();
    for(const low of [false,true])for(const big of [false,true])for(const accent of [null,0,0xb03030])for(const padding of [0,low?limits.low:limits.normal]) {
      setLowPower(low);let draws=0;Math.random=()=>random[(draws++)%random.length];
      effects.push(...Array.from({length:padding},()=>({obj:null,ttl:100,age:0})));
      const point=[12,20,-9];fx.debrisBurst(scene,effects,...point,{big,accent});
      const initial=states(),steps=[];
      for(const delta of [0,.016,.12,.2,.1,.3,.09,.3,.4]) {
        // Budget padding is a source list entry; a no-op retirement keeps it out of the scene.
        BattleClient.prototype._updateEffects.call({effects,scene,_freeEffect(effect){if(effect.obj)BattleClient.prototype._freeEffect.call(this,effect);}},delta);
        steps.push({delta,count:effects.length,effects:states()});
      }
      debris.push({low,big,accent,padding,point,random,draws,initial,steps});
      for(let i=effects.length-1;i>=0;i--)if(!effects[i].obj)effects.splice(i,1);
      release();
    }
    const keys={},sizes={},lifetimes={};
    for(const big of [false,true])for(const hue of [0,2,18,48])for(let index=0;index<4;index++) {
      Math.random=()=>index/4;fx.comicPop(scene,effects,12,20,-9,{big,hue});
      const object=effects[0].obj,key=`comic-${big?'big':'small'}-${hue}-${index}`;
      textures[key]=object.material.map.image.toDataURL('image/png').split(',')[1];
      textureKeys.set(object.material.map,key);
      keys[`${big?'big':'small'}/${hue}`]??=[];keys[`${big?'big':'small'}/${hue}`].push(key);
      sizes[big?'big':'small']=object.userData.size;lifetimes[big?'big':'small']=object.userData.ttl;
      release();
    }
    for(const big of [false,true])for(const padding of [0,limits.normal,limits.maximum+3])for(const offset of [0,1,2,3,4]) {
      const samples=random.map((_,index)=>random[(index+offset)%random.length]);
      setLowPower(false);let draws=0;Math.random=()=>samples[(draws++)%samples.length];
      effects.push(...Array.from({length:padding},()=>({obj:null,ttl:100,age:0})));
      fx.comicPop(scene,effects,12,20,-9,{big,hue:2});
      const initial=states(),steps=[];
      for(const delta of [0,.016,.059,.075,.15,.15,.15,.31]) {
        BattleClient.prototype._updateEffects.call({effects,scene,_freeEffect(effect){if(effect.obj)BattleClient.prototype._freeEffect.call(this,effect);}},delta);
        steps.push({delta,count:effects.length,effects:states()});
      }
      comics.push({big,hue:2,padding,point:[12,20,-9],random:samples,draws,initial,steps});
      for(let i=effects.length-1;i>=0;i--)if(!effects[i].obj)effects.splice(i,1);
      release();
    }
    const sceneProfiles={},sceneBursts=[],collapseFrames=[];
    for(const kind of [...new Set([...Object.keys(d.UNITS),...Object.keys(d.HAZARDS),...Object.keys(d.SCENE_STRUCT.TYPE),
      'mapbuilding','tree','moon','slab','decoy','kami','hyper','decoy_beacon','missile','unknown'])]) {
      const profile=sceneDamage.sceneDamageProfile(kind);
      if(profile)sceneProfiles[kind]=profile;
    }
    for(const kind of ['car','rockfall','fallentree','tower','soldier','mapbuilding','unknown'])
      for(const id of [42,43,4294967295])for(const stage of [1,2,3])for(const low of [false,true]) {
        setLowPower(low);let draws=0;Math.random=()=>{draws++;return .5;};
        const point=[12,20,-9],height=6,radius=12;
        sceneDamage.sceneDamageBurst(scene,effects,{id,kind,mesh:{position:new THREE.Vector3(...point)},dimH:height,dimR:radius},stage);
        const initial=states(),steps=[];
        for(const delta of [0,.016,.12,.2,.1,.3,.4,.4]) {
          BattleClient.prototype._updateEffects.call({effects,scene,_freeEffect:BattleClient.prototype._freeEffect},delta);
          steps.push({delta,count:effects.length,effects:states()});
        }
        sceneBursts.push({id,kind,stage,low,point,height,radius,draws,initial,steps});release();
      }
    for(const id of [42,43])for(const instant of [false,true])for(const evict of [false,true]) {
      const mesh=new THREE.Mesh(new THREE.BoxGeometry(2,6,2),new THREE.MeshBasicMaterial());
      const scale=[1.2,1.7,.9],rotation=[.13,.21,-.17];mesh.scale.fromArray(scale);mesh.rotation.set(...rotation);
      const client={scene,effects,damaged:new Set(),_freeEffect:BattleClient.prototype._freeEffect};
      const ent={id,kind:'car',neutral:true,mesh,dimH:6,dimR:12,colR:12,colH:6};
      BattleClient.prototype._applyCollapse.call(client,ent,instant);
      const frames=[];
      for(const [index,delta]of [0,.016,0,.12,.2,.1,.3].entries()) {
        if(evict&&index===1)effects.push(...Array.from({length:limits.maximum},()=>({obj:new THREE.Group(),ttl:100,age:0})));
        BattleClient.prototype._updateEffects.call(client,delta);
        frames.push({delta,scale:mesh.scale.toArray(),rotation:mesh.rotation.toArray().slice(0,3)});
      }
      collapseFrames.push({id,instant,evict,scale,rotation,frames});release();disposeTree(mesh);
    }
    return {graphs,textures,rules:{palette,comicKeys:keys,sizes,lifetimes,sceneProfiles,damageThresholds:fx.DMG_FX},
      fixtures:{mechanicalDebris:debris,comicPops:comics,sceneBursts,collapseFrames}};
  } finally {
    Math.random=previous;
    for(let i=effects.length-1;i>=0;i--)if(!effects[i].obj)effects.splice(i,1);
    release();
    if(stored==null)localStorage.removeItem('svs_lowpower');else localStorage.setItem('svs_lowpower',stored);
  }
}
