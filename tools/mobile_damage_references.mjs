// Original mobile damage owns all expected tint, local-scar, cap and release results.
export function captureMobileDamage({THREE,toon,sceneDamage,graphOf,disposeTree}) {
  const mobileDamageGeometry=[];
  for(const kind of ['robot','soldier','decoy','unknown'])for(const indexed of [false,true]) {
    const root=new THREE.Group();root.position.set(12,20,-9);root.rotation.y=.4;
    let geometry=new THREE.BoxGeometry(3,6,2,1,2,1);
    if(!indexed){const unindexed=geometry.toNonIndexed();geometry.dispose();geometry=unindexed;}
    const opaque=new THREE.MeshBasicMaterial({color:0x9d7351});
    const transparent=new THREE.MeshBasicMaterial({color:0x4298d1,transparent:true,opacity:.4});
    const nodes=[];
    for(let index=0;index<26;index++) {
      let material=index===5?transparent:index===6?[opaque]:index===9?[opaque,transparent,opaque,opaque,transparent,opaque]:opaque;
      let node=index===7?new THREE.SkinnedMesh(geometry,material):index===8?new THREE.InstancedMesh(geometry,material,3):new THREE.Mesh(geometry,material);
      if(index===2) {
        const owner=toon.outlinify(node);
        const shell=owner.children.find(child=>child.userData.isOutline);
        if(!shell)throw new Error('Original mobile-damage outline exclusion fixture has no source shell');
        owner.remove(shell);node=shell;
      }
      node.name='part'+index;
      node.position.set(Math.fround(index*.37),Math.fround(index*.11),Math.fround(-index*.21));
      if(index===1)node.userData.noPaint=true;
      if(index===3)node.userData.teamRing=true;
      if(index===4)node.userData.weatherScorch=true;
      if(node.isInstancedMesh)for(let slot=0;slot<3;slot++)node.setMatrixAt(slot,new THREE.Matrix4().makeTranslation(slot*2,slot*.5,0));
      root.add(node);nodes.push(node);
    }
    root.updateMatrixWorld(true);
    const graph=graphOf(root).data,ent={id:42,kind,mesh:root,dimH:6,dimR:3},steps=[];
    const capture=()=>{
      root.updateMatrixWorld(true);
      const matrix=new THREE.Matrix4();
      return {stage:ent.sceneStage??-1,colours:nodes.map(node=>(Array.isArray(node.material)?node.material:[node.material]).map(material=>material.color.toArray())),
        instances:Array.from({length:3},(_,slot)=>{nodes[8].getMatrixAt(slot,matrix);return matrix.toArray();}),
        scars:(ent.mobileDamage?.scars??[]).map(scar=>({owner:scar.parent.name,positions:Array.from(scar.geometry.attributes.position.array),
          visible:scar.visible,opacity:scar.material.opacity,count:Number.isFinite(scar.geometry.drawRange.count)?scar.geometry.drawRange.count:scar.geometry.attributes.position.count,
          world:scar.matrixWorld.toArray()}))};
    };
    const initial=capture();
    for(const action of [{stage:0},{release:true},{stage:1},{stage:1},{stage:2},{move:true,stage:2},{stage:0},{stage:3},{release:true},{stage:1},{release:true}]) {
      if(action.move){nodes[0].position.y+=.5;nodes[0].rotation.z+=.25;nodes[8].setMatrixAt(1,new THREE.Matrix4().makeTranslation(8,4,2));}
      if(action.release)sceneDamage.releaseMobileDamage(ent);else sceneDamage.applySceneDamage(ent,action.stage);
      steps.push({...action,result:capture()});
    }
    mobileDamageGeometry.push({kind,indexed,graph,initial,steps});
    sceneDamage.releaseMobileDamage(ent);disposeTree(root);
  }
  return {mobileDamageGeometry};
}
