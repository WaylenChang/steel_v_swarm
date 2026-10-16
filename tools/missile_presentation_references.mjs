// Actual client snapshot and render methods own visual lifecycle expectations.
export function captureMissilePresentation({THREE,d,fx,sceneDamage,BattleClient,graphOf,disposeTree,limits}) {
  const previousRandom=Math.random;
  const graphs={},projectileGraphs={},profiles={},missilePresentation=[];
  const ground=(x,z)=>5+x*.1-z*.2;
  let bursts=[];
  const sync=new Function('THREE','projectileMesh','sceneDamageStage','sceneDamageBurst','applySceneDamage','releaseMobileDamage','disposeTree',
    'return function '+BattleClient.prototype._syncMissiles.toString())(THREE,fx.projectileMesh,sceneDamage.sceneDamageStage,
      (_scene,_effects,entity,stage)=>bursts.push({id:entity.id,stage,position:entity.mesh.position.toArray(),height:entity.dimH,radius:entity.dimR}),
      sceneDamage.applySceneDamage,sceneDamage.releaseMobileDamage,disposeTree);
  const update=new Function('THREE','lerpFPS','stepProjectileFx','return function '+BattleClient.prototype._updateMissiles.toString())(THREE,d.lerpFPS,fx.stepProjectileFx);
  const tickEffects=new Function('FX_MAX','return function '+BattleClient.prototype._updateEffects.toString())(limits.maximum);
  const context=()=>({scene:new THREE.Scene(),effects:[],samMeshes:new Map(),damaged:new Set(),terrain:{heightAt:ground},
    _updateDamageStage:BattleClient.prototype._updateDamageStage,_freeEffect:BattleClient.prototype._freeEffect});
  const clean=client=>{sync.call(client,[]);for(const effect of client.effects.splice(0))client._freeEffect(effect);};
  try {
    Math.random=()=>.5;
    const client=context();sync.call(client,[{id:7,x:12,z:9,y:10,hp:100,m:100}]);
    const source=client.samMeshes.get(7),mesh=source.mesh;
    const metadata={scale:mesh.scale.x,dimensions:{height:source.dimH,top:source.dimTop,radius:source.dimR}};
    const snapshot=BattleClient.prototype._applySnap.toString();
    const seams=[['view',snapshot.indexOf('this._onSelfDeath();')],['boom',snapshot.indexOf('for (const ev of m.ev || []) this._onEvent(ev);')],
      ['fracture',snapshot.indexOf('this._syncMissiles(m.sm || [],m.ev || []);')]];
    if(seams.some(([,index])=>index<0))throw new Error('Missing original snapshot publication seams');
    metadata.publicationOrder=seams.sort((a,b)=>a[1]-b[1]).map(([name])=>name);
    mesh.position.set(0,0,0);mesh.scale.setScalar(1);mesh.updateMatrixWorld(true);
    const graph=graphOf(mesh,true),animation=mesh.userData.projectileFx;
    const rayMethod=BattleClient.prototype._rayCandidates.toString();
    const missileRay=rayMethod.slice(rayMethod.indexOf('for (const [mid, ms] of this.samMeshes)'));
    const radius=/if \(s < -([\d.]+) \|\| s > far \+ ([\d.]+)\)/.exec(missileRay);
    const squared=/if \(dx \* dx \+ dy \* dy \+ dz \* dz > ([\d.]+)\)/.exec(missileRay);
    if(!radius||!squared||Number(radius[1])!==Number(radius[2])||Number(radius[1])**2!==Number(squared[1]))
      throw new Error('Original missile broad-phase sphere changed');
    metadata.rayRadius=Number(radius[1]);metadata.rayParts=[];
    const minimap=BattleClient.prototype._drawMinimap.toString();
    const marker=/ctx.fillStyle = '#([0-9a-f]+)';\s*for \(const ms of this.samMeshes.values\(\)\)/.exec(minimap);
    const size=/ctx.fillRect\(mx - ([\d.]+), my - ([\d.]+), ([\d.]+), ([\d.]+)\)/.exec(minimap.slice(marker?.index??minimap.length));
    if(!marker||!size||Number(size[1])*2!==Number(size[3])||Number(size[2])*2!==Number(size[4]))
      throw new Error('Original missile minimap marker changed');
    metadata.minimap={color:parseInt(marker[1],16),size:[Number(size[3]),Number(size[4])]};
    mesh.updateMatrixWorld(true);
    mesh.traverse(node=>{
      if(!node.isMesh)return;
      if(node.isSkinnedMesh||node.isInstancedMesh)throw new Error('Missile ray capture requires explicit skin/instance semantics');
      let anchor=node;while(!graph.ids.has(anchor)&&anchor.parent)anchor=anchor.parent;
      if(!graph.ids.has(anchor))throw new Error('Missing missile ray animation anchor');
      const relative=anchor===node?new THREE.Matrix4():new THREE.Matrix4().multiplyMatrices(anchor.matrixWorld.clone().invert(),node.matrixWorld);
      const position=node.geometry.attributes.position,positions=[],point=new THREE.Vector3();
      for(let i=0;i<position.count;i++)positions.push(...point.fromBufferAttribute(position,i).applyMatrix4(relative).toArray());
      const raw=node.geometry.index?[...node.geometry.index.array]:Array.from({length:position.count},(_,i)=>i);
      const array=Array.isArray(node.material),groups=array?node.geometry.groups:[{start:0,count:raw.length,materialIndex:0}];
      const from=node.geometry.drawRange.start,to=from+node.geometry.drawRange.count;
      for(const group of groups) {
        const material=array?node.material[group.materialIndex]:node.material;
        if(!material)continue;
        const start=Math.max(group.start,from),end=Math.min(raw.length,group.start+group.count,to);
        metadata.rayParts.push({node:graph.ids.get(anchor),positions,indices:raw.slice(start,end),side:material.side});
      }
    });
    projectileGraphs['sam-source']=graph.data;
    profiles['sam-source']={character:null,slot:'light',side:'',heavy:!!animation?.heavy,phase:animation?.phase||0,
      authored:(animation?.authored||[]).map(node=>graph.ids.get(node)),wake:graph.ids.get(animation?.wake)??-1,
      jets:(animation?.jets||[]).map(jet=>({node:graph.ids.get(jet.mesh),rad:jet.rad,len:jet.len,opacity:jet.opacity,nozzle:jet.nozzle}))};
    clean(client);
    const puff=new THREE.Mesh(new THREE.SphereGeometry(.5,5,4),new THREE.MeshBasicMaterial({color:0xcfd6da,transparent:true,opacity:.5}));
    graphs.missile_smoke=graphOf(puff).data;disposeTree(puff);
    for(const terminal of ['silent','impact','intercept','deflect','wrong']) {
      const view=context(),steps=[];let draws=0;Math.random=()=>{draws++;return .5;};
      const capture=()=>({draws,bursts:bursts.slice(),missiles:[...view.samMeshes.values()].map(entity=>({id:entity.id,
        position:entity.mesh.position.toArray(),target:entity.tgt.toArray(),previous:entity.prev.toArray(),quaternion:entity.mesh.quaternion.toArray(),
        age:entity.age,smoke:entity.smoke??0,stage:entity.sceneStage??-1,fxStage:entity.dmgStage??0,fx:!!entity.dmgFx,
        nodes:entity.mesh.children.filter(node=>node.isMesh&&!node.userData.isOutline).map(node=>({position:node.position.toArray(),scale:node.scale.toArray(),opacity:node.material.opacity}))})),
        effects:view.effects.map(effect=>({position:effect.obj.position.toArray(),scale:effect.obj.scale.toArray(),ttl:effect.ttl,age:effect.age??0,opacity:effect.obj.material.opacity}))});
      const packets=[{x:12,y:10,z:9,hp:100,m:100,dt:.06},{x:12,y:10.7,z:9,hp:100,m:100,dt:0},
        {x:12,y:11.5,z:9,hp:100,m:100,dt:0},{x:13,y:10,z:9,hp:49,m:100,dt:.000001},
        {x:13,y:10,z:9,hp:49,m:100,dt:.016},{x:13.5,y:10.5,z:9,hp:24,m:100,dt:0},
        {x:14,y:11,z:9,hp:26,m:100,dt:.1},{x:14,y:11,z:9,hp:'NAN',m:100,dt:.2},
        {x:15,y:12,z:10,hp:20,m:0,dt:.06},{x:15,y:12,z:10,hp:0,m:100,dt:.4}];
      for(const packet of packets) {
        bursts=[];const state={...packet,id:7,hp:packet.hp==='NAN'?NaN:packet.hp};delete state.dt;
        sync.call(view,[state]);update.call(view,packet.dt);tickEffects.call(view,packet.dt);
        steps.push({states:[{id:7,position:[state.x,state.y,-state.z],hp:packet.hp,max_hp:state.m}],delta:packet.dt,reports:[],result:capture()});
      }
      const event=terminal==='silent'?[]:[{e:'boom',...(terminal==='deflect'?{}:{missileId:terminal==='wrong'?99:7})}];
      const reports=terminal==='silent'?[]:[{type:terminal==='deflect'?'missile_deflect':terminal==='intercept'?'missile_intercept':'missile_blast',missile:terminal==='wrong'?99:7}];
      bursts=[];sync.call(view,[],event);steps.push({states:[],reports,delta:0,result:capture()});
      bursts=[];sync.call(view,[],event);steps.push({states:[],reports,delta:0,result:capture()});
      missilePresentation.push({terminal,steps});clean(view);
    }
    const missileViewRays=[];
    for(const health of [100,49,24])for(const duplicate of [false,true]) {
      const view=context();view.ents=new Map();view.side='STEEL';const frames=[];
      const packets=[{x:12,y:10,z:9,hp:100,delta:0},{x:13,y:11.5,z:9,hp:health,delta:.016},
        {x:14,y:12,z:10,hp:health,delta:.1},{x:14,y:12,z:10,hp:health,delta:0}];
      for(const [frame,packet]of packets.entries()) {
        const states=[{id:7,x:packet.x,y:packet.y,z:packet.z,hp:packet.hp,m:100},
          {id:8,x:packet.x+(duplicate?0:18),y:packet.y,z:packet.z,hp:packet.hp,m:100}];
        sync.call(view,states);update.call(view,packet.delta);if(frame===3)view.samMeshes.get(7).mesh.visible=false;
        view.scene.updateMatrixWorld(true);
        const point=view.samMeshes.get(7).mesh.position.clone(),rays=[];
        const offsets=[[0,0,-10],[10,0,0],[0,10,0],[0,-10,0],[0,0,10],[0,0,0],[.3,.2,-10]];
        const inputs=offsets.map(offset=>({origin:point.clone().add(new THREE.Vector3(...offset)),far:20,
          direction:new THREE.Vector3(...offset).negate().normalize()}));
        inputs[5].direction.set(0,0,1);inputs[5].far=.05;
        for(const x of [6,6.00001])inputs.push({origin:point.clone().add(new THREE.Vector3(x,0,-10)),direction:new THREE.Vector3(0,0,1),far:20});
        for(const z of [-26,-26.00001])inputs.push({origin:point.clone().add(new THREE.Vector3(0,0,z)),direction:new THREE.Vector3(0,0,1),far:20});
        for(const input of inputs) {
          const candidates=BattleClient.prototype._rayCandidates.call(view,input.origin,input.direction,input.far,[]);
          const ray=new THREE.Raycaster(input.origin,input.direction,0,input.far);
          const camera=new THREE.PerspectiveCamera(60,1,.01,100);camera.position.copy(input.origin);
          camera.lookAt(input.origin.clone().add(input.direction));camera.updateMatrixWorld(true);ray.camera=camera;
          const hit=ray.intersectObjects(candidates,true).find(item=>item.object.isMesh===true);
          let root=hit?.object;while(root&&root.userData.missileId==null&&root.parent)root=root.parent;
          rays.push({origin:input.origin.toArray(),direction:input.direction.toArray(),far:input.far,
            candidates:candidates.map(root=>root.userData.missileId),point:hit?.point.toArray()??null,missile:root?.userData.missileId??0});
        }
        frames.push({states:states.map(state=>({id:state.id,position:[state.x,state.y,-state.z],hp:state.hp,max_hp:state.m})),delta:packet.delta,hidden:frame===3,rays});
      }
      missileViewRays.push({health,duplicate,frames});clean(view);
    }
    return {graphs,projectileGraphs,profiles,metadata,fixtures:{missilePresentation,missileViewRays}};
  } finally {Math.random=previousRandom;}
}
