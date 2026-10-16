// Execute the original geometry implementation; snapshots contain no native expectations.
export function captureSceneDamage({THREE,d,fx,sceneDamage,BattleClient,graphOf,disposeTree}) {
  const sceneDamageGeometry=[],sceneDamageStages=[],sceneDamageObservations=[];
  for(const hp of [-1,0,.001,24.999,25,25.001,49.999,50,50.001,100,101])
    for(const maximum of [-1,0,100])for(const collapsed of [false,true])
      sceneDamageStages.push({hp,maximum,collapsed,stage:sceneDamage.sceneDamageStage(hp,maximum,collapsed)});
  const capture=ent=>({stage:ent.sceneStage??-1,nodes:ent.inputNodes.map(node=>({
    positions:Array.from(node.geometry.attributes.position.array),
    normals:node.geometry.attributes.normal?Array.from(node.geometry.attributes.normal.array):[],
    colours:(Array.isArray(node.material)?node.material:[node.material]).map(material=>material.color.toArray())})),
    cracks:ent.sceneDamageCracks?{visible:ent.sceneDamageCracks.visible,
      positions:Array.from(ent.sceneDamageCracks.geometry.attributes.position?.array??[])}:null});
  for(const kind of ['car','rockfall','fallentree','tower','mapbuilding','unknown'])
    for(const neutral of [false,true])for(const id of [42,43])for(const shape of ['shared','nonindexed','groups','mirrored','late']) {
      const root=new THREE.Group();root.position.set(12,20,-9);root.rotation.y=.4;root.scale.set(1.2,.9,1.1);
      const geometry=new THREE.BoxGeometry(3,6,2,1,2,1);
      geometry.translate(0,2.5,0);
      const source=shape==='nonindexed'?geometry.toNonIndexed():geometry;
      if(shape==='nonindexed')geometry.dispose();
      const material=new THREE.MeshBasicMaterial({color:0x9d7351});
      const transparent=new THREE.MeshBasicMaterial({color:0x4298d1,transparent:true,opacity:.4});
      const nodes=[];
      for(let index=0;index<4;index++) {
        const materials=shape==='groups'&&index===0?[material,transparent,material,material,transparent,material]:material;
        const node=new THREE.Mesh(source,materials);node.name='part'+index;
        node.position.set(Math.fround(index*.37),Math.fround(index*.11),Math.fround(-index*.21));
        node.scale.set(index===1&&shape==='mirrored'?-1:1,1,1);
        if(index===2)node.userData.teamRing=true;
        if(index===3)node.userData.weatherScorch=true;
        root.add(node);nodes.push(node);
      }
      const ent={id,kind,neutral,mesh:root,dimR:3,dimH:6,inputNodes:nodes};
      root.updateMatrixWorld(true);
      const graph=graphOf(root).data,initial=capture(ent),steps=[];
      for(const stage of [0,1,1,2,0,3,1,0]) {
        sceneDamage.applySceneDamage(ent,stage);
        const late=shape==='late'&&steps.length===0;
        if(late){const node=new THREE.Mesh(source.clone(),material.clone());node.name='late';node.position.x=8;root.add(node);}
        steps.push({stage,late,result:capture(ent)});
      }
      sceneDamageGeometry.push({kind,id,neutral,shape,dimensions:{radius:3,height:6},graph,initial,steps});
      disposeTree(root);
    }
  const snapshot=BattleClient.prototype._applySnap.toString();
  const start=snapshot.indexOf('      const prevHpSnap = ent.hp;');
  const end=snapshot.indexOf('      ent.lk = !!e.lk;',start);
  if(start<0||end<=start)throw new Error('Missing original snapshot damage-stage seam');
  const shieldStart=snapshot.indexOf('const _spDrop ='),shieldEnd=snapshot.indexOf('ent.sp = e.sp',shieldStart);
  if(shieldStart<0||shieldEnd<=shieldStart)throw new Error('Missing original hero contact seam');
  let bursts=[],order=[];
  const observe=new Function('HERO_KINDS','shieldHitStrength','sceneDamageProfile','sceneDamageStage','sceneDamageBurst','applySceneDamage',
    'return function(e,ent){'+snapshot.slice(start,end)+'if(HERO_KINDS.has(e.k)){'+snapshot.slice(shieldStart,shieldEnd)+'}}')(
      new Set(Object.values(d.CHARACTERS).map(character=>character.kind)),fx.shieldHitStrength,
      sceneDamage.sceneDamageProfile,sceneDamage.sceneDamageStage,
      (_scene,_effects,_ent,stage)=>{bursts.push(stage);order.push('damage');},sceneDamage.applySceneDamage);
  for(const kind of ['car','robot','soldier'])for(const collapsed of [false,true]) {
    const root=new THREE.Group(),mesh=new THREE.Mesh(new THREE.BoxGeometry(3,6,2),new THREE.MeshBasicMaterial({color:0x9d7351}));
    mesh.name='part0';root.add(mesh);root.updateMatrixWorld(true);
    const hero=kind==='robot',mobile=!!sceneDamage.sceneDamageProfile(kind)?.mobile;
    const graph=graphOf(root).data,ent={id:42,kind,hero,mesh:root,neutral:true,dimH:6,dimR:3,collapsed,hp:100,max:100,sp:0};
    sceneDamage.applySceneDamage(ent,0);
    const steps=[];
    for(const [index,hp]of [100,50,50,25,25.001,0,100,75,24,20].entries()) {
      const initial=index===8&&!collapsed;
      if(initial){ent.hp=hp;sceneDamage.applySceneDamage(ent,sceneDamage.sceneDamageStage(hp,100));}
      bursts=[];order=[];
      observe.call({scene:null,effects:null,_victimHitFx(){order.push('victim');}},{k:kind,hp,m:100,sp:0,dead:hp<=0},ent);
      steps.push({hp,initial,stage:ent.sceneStage,bursts,order});
    }
    sceneDamageObservations.push({kind,hero,mobile,collapsed,graph,steps});
    sceneDamage.releaseMobileDamage(ent);disposeTree(root);
  }
  return {sceneDamageGeometry,sceneDamageStages,sceneDamageObservations};
}
