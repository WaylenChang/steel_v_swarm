// Offline source execution. Runtime receives native scene geometry and scalar animation data.
export function captureHeroShotReferences({THREE,d,assets,fx,BattleClient,source,sampleKeys,graphOf,disposeTree,setLowPower,limits}) {
  const shapes={},characters={},graphs={},projectiles={},profiles={},geometry=[],projectileFx=[],cases=[],ionCases=[];
  const scene=new THREE.Scene(),effects=[];
  const clear=()=>{for(const effect of effects.splice(0))if(effect.obj)BattleClient.prototype._freeEffect.call({scene},effect);};
  const discharge=new Function('THREE','COMBAT_ASSETS','unitGeo','sampleCombatKeys','starburst','_FWD',
    source+'\nreturn combatDischarge;')(THREE,assets,(_key,create)=>create(),sampleKeys,fx.starburst,new THREE.Vector3(0,0,1));
  const previousPower=localStorage.getItem('svs_lowpower'),previousRandom=Math.random;
  const snapshot=(effect,includeGeometry=false)=>{
    const node=effect.obj,meshes=[];
    node.traverse(part=>{if(!part.isMesh)return;
      const row={position:part.position.toArray(),quaternion:part.quaternion.toArray(),scale:part.scale.toArray(),
        opacity:part.material.opacity,color:part.material.color.getHex()};
      if(includeGeometry){row.vertices=[...part.geometry.attributes.position.array];
        row.indices=part.geometry.index?[...part.geometry.index.array]:Array.from({length:part.geometry.attributes.position.count},(_,index)=>index);}
      if(part.geometry.attributes.color)row.colors=[...part.geometry.attributes.color.array];
      meshes.push(row);
    });
    const result={type:node.isSprite?'spark':node.isInstancedMesh?'rings':node.userData.authoredFan?'authored_fan':node.userData.authoredDischarge?'authored_discharge':
      node.isGroup?'lance_projectile':node.geometry.type==='RingGeometry'?'shock':node.geometry.parameters.radialSegments===6?'beam':node.material.opacity===.42?'halo':'core',
      position:node.position.toArray(),quaternion:node.quaternion.toArray(),scale:node.scale.toArray(),visible:node.visible,
      opacity:node.material?.opacity??null,color:node.material?.color.getHex()??null,
      roll:node.isSprite?node.material.rotation:null,meshes};
    if(node.isInstancedMesh) {
      result.instances=Array.from({length:node.count},(_,index)=>{
        const matrix=new THREE.Matrix4();node.getMatrixAt(index,matrix);return matrix.toArray();});
      result.instanceColors=node.instanceColor?Array.from({length:node.count},(_,index)=>{
        const color=new THREE.Color();node.getColorAt(index,color);return color.toArray();}):[];
    }
    return result;
  };
  const definition=(character,slot,level)=>{
    const value=d.heroWeapon(character,slot,level);
    return {...value,trajectory:d.trajClass(value),lanceRadius:d.lanceR(value),fanSubs:d.fanSubs(value),
      fanRangeFactors:Array.from({length:d.fanSubs(value)},(_,bin)=>d.fanBinRangeF(value,bin)),
      projectile:{speed:d.shotV0(value)}};
  };
  try {
    setLowPower(false);Math.random=()=>.25;
    for(const character of Object.keys(d.CHARACTERS)) {
      const asset=assets[character];if(!asset)continue;
      const info={accent:new THREE.Color(asset.combat.intent.accent).getHex(),hue:d.CHARACTERS[character].visual?.hue??null,
        charging:!!asset.combat.charging?.length,shapes:{light:{},heavy:{}},payloads:{}};
      characters[character]=info;
      for(const slot of ['light','heavy']) {
        const def=d.heroWeapon(character,slot,1);
        for(const family of ['beam','bullet','ion']) {
          clear();
          if(!discharge(scene,effects,new THREE.Vector3(),new THREE.Vector3(0,0,1),def,family,1,.5))continue;
          const key=character+'-'+slot+'-'+family;
          graphs[key]=graphOf(effects[0].obj,true).data;
          shapes[key]={family,character,slot,envelope:asset.combat.clips[slot].envelope};
          info.shapes[slot][family]=key;
        }
        clear();
        if(fx.fanDischarge(scene,effects,new THREE.Vector3(),new THREE.Vector3(0,0,1),def,{range:1})) {
          const key=character+'-'+slot+'-fan',group=effects[0].obj,graph=graphOf(group,true);
          const parts=asset.meshes.filter(part=>part.parent===`fx_${slot}_ion`),ownership=asset.combat.fans[slot];
          group.children.forEach((node,index)=>{
            const row=graph.data.nodes.find(row=>row.id===graph.ids.get(node)),part=parts[index];
            row.effect={positions:part.positions,bins:ownership.vertexBins[part.material]};
          });
          const {vertexBins,...animation}=ownership;
          graphs[key]=graph.data;shapes[key]={family:'fan',character,slot,ownership:animation};info.shapes[slot].fan=key;
        }
        if(asset.combat.payloads?.[slot]) {
          const key='discharge-'+character+'-'+slot;
          const mesh=fx.projectileMesh(def,{hue:info.hue??0xffd27a,heavy:true});
          const graph=graphOf(mesh,true),motion=mesh.userData.projectileFx;
          projectiles[key]=graph.data;geometry.push({key,nodes:graph.data.nodes});
          profiles[key]={character,slot,side:'',heavy:!!motion?.heavy,phase:motion?.phase||0,
            authored:(motion?.authored||[]).map(node=>graph.ids.get(node)),wake:graph.ids.get(motion?.wake)??-1,
            jets:(motion?.jets||[]).map(jet=>({node:graph.ids.get(jet.mesh),rad:jet.rad,len:jet.len,opacity:jet.opacity,nozzle:jet.nozzle}))};
          for(const age of [0,.17])for(const speed of [0,500]) {
            fx.stepProjectileFx(mesh,age,speed);
            projectileFx.push({key,age,speed,nodes:[...graph.ids].filter(([node])=>node.isMesh).map(([node,id])=>
              ({id,position:node.position.toArray(),scale:node.scale.toArray(),opacity:node.material.opacity}))});
          }
          info.payloads[slot]=key;disposeTree(mesh);
        }
      }
    }
    for(const [character,hero]of Object.entries(d.CHARACTERS))for(const slot of ['light','heavy'])for(const level of [1,4]) {
      const def=definition(character,slot,level),kind=d.aoeClass(def);
      if(!['fan','line'].includes(kind))continue;
      for(const scenario of ['clear','wall','up','zero','crowded','full']) {
        clear();setLowPower(false);
        const padding=scenario==='crowded'?limits.normal-1:scenario==='full'?limits.normal:0;
        effects.push(...Array.from({length:padding},()=>({obj:null})));
        const origin=new THREE.Vector3(12,20,-9),direction=new THREE.Vector3(...(scenario==='up'?[0,1,0]:scenario==='zero'?[0,0,0]:[0,0,1]));
        const target=origin.clone().addScaledVector(direction,def.range),queries=[];
        const clip=(from,to)=>{
          const result=BattleClient.prototype._clipBeam.call({_obstHitT(ax,ay,az,bx,by,bz){
            if(scenario!=='wall'||az===bz)return null;
            const t=(30-az)/(bz-az);return t>=0&&t<=1?t*Math.hypot(bx-ax,by-ay,bz-az):null;
          }},from,to);
          queries.push({from:from.toArray(),to:to.toArray(),result:{to:result.to.toArray(),cut:result.cut}});return result;
        };
        let accepted=true;
        if(kind==='fan')accepted=fx.fanDischarge(scene,effects,origin,direction,def,{range:def.range,clip});
        else fx.lanceDischarge(scene,effects,origin,clip(origin,target).to,def,hero.visual?.hue??0x4fc3f7);
        const created=effects.slice(padding),initial=created.map(entry=>({ttl:entry.ttl,...snapshot(entry,true)})),steps=[];
        for(const progress of [0,.09,.2,.5,.9,1,1.2]) {
          created.forEach(entry=>entry.fade?.(entry.obj,Math.max(0,1-progress),.016));
          steps.push({progress,effects:created.map(entry=>snapshot(entry))});
        }
        cases.push({kind,character,slot,level,padding,scenario,definition:def,accepted,origin:origin.toArray(),direction:direction.toArray(),
          target:target.toArray(),color:hero.visual?.hue??0x4fc3f7,queries,initial,steps});
      }
    }
    const ionDefinitions=[null,...Object.entries(characters).flatMap(([character,info])=>
      ['light','heavy'].filter(slot=>info.shapes[slot].ion).map(slot=>definition(character,slot,1)))];
    for(const def of ionDefinitions)for(const low of [false,true])for(const scenario of ['clear','vertical','near','zero','crowded','full']) {
      for(const coil of (def?[3]:[0,.5,2.5,9])) {
        clear();setLowPower(low);
        const padding=['crowded','full'].includes(scenario)?(low?limits.low:limits.normal)-(scenario==='crowded'?1:0):0;
        effects.push(...Array.from({length:padding},()=>({obj:null})));
        const origin=new THREE.Vector3(12,20,-9),target=origin.clone().add(new THREE.Vector3(...(
          scenario==='zero'?[0,0,0]:scenario==='near'?[.005,0,0]:scenario==='vertical'?[0,80,0]:[40,10,90])));
        fx.ionBreath(scene,effects,origin,target,0x7fe8ff,{r:2.2,ttl:.45,coil,core:0xfff3d0,def:def??undefined});
        const created=effects.slice(padding);
        const types=created.map((effect,index)=>effect.obj.userData.authoredDischarge?'authored_discharge':effect.obj.isSprite?'spark':
          ['ion_throat','ion_core','ion_beads','ion_arcs'][index]);
        const initial=created.map((effect,index)=>({ttl:effect.ttl,...snapshot(effect,true),type:types[index]})),steps=[];
        for(const progress of [0,.17,.5,.9,1,1.2]) {
          created.forEach(effect=>effect.fade?.(effect.obj,Math.max(0,1-progress),.016));
          steps.push({progress,effects:created.map((effect,index)=>({...snapshot(effect),type:types[index]}))});
        }
        ionCases.push({definition:def,low,scenario,coil,padding,origin:origin.toArray(),target:target.toArray(),initial,steps});
      }
    }
  } finally {
    clear();Math.random=previousRandom;
    if(previousPower==null)localStorage.removeItem('svs_lowpower');else localStorage.setItem('svs_lowpower',previousPower);
  }
  return {graphs,shapes,characters,projectiles,profiles,geometry,projectileFx,fixtures:{heroShotEffects:cases,ionBreathEffects:ionCases}};
}
