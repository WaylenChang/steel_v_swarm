// Offline components use original NPC builders, geometry and surface finishing.
export function captureCivilianBodies({THREE,d,methods,geo,limbChain,finishUnitSurfaces,sceneryGeometry,
  generateCivilian,options,kits,outlinify,enableDissolve,makeUnit,graphOf,measure,stepCombatFx,stepLocomotion,disposeTree}) {
  const graphs={},profiles={},fixtures=[];
  const palette={skinColor:0xb5816d,hairColor:0x293b57,clothColor:0x689f3c,trouserColor:0xa04c83,accentColor:0xe1b236};
  let appearance={...generateCivilian(0,0),...palette,widthScale:1,shoulderScale:1,headScale:1};
  const scope={THREE,...geo,limbChain,sceneryGeometry,CIVILIANS:d.CIVILIANS,CIVILIAN_PROFESSION_KITS:kits,TAU:Math.PI*2};
  const helpers=new Function(...Object.keys(scope),[methods.frustum,methods.strut,methods.glowPlate,methods.markBatch,
    methods.civilianSurface,methods.addCivilianHair,methods.addCivilianClothing,methods.addProfessionKit,
    'return {hair:addCivilianHair,clothes:addCivilianClothing,profession:addProfessionKit};'].join('\n'))(...Object.values(scope));
  const mainScope={...scope,generateCivilian:()=>appearance,addCivilianHair:()=>{},addCivilianClothing:()=>{},addProfessionKit:()=>null};
  const buildMain=new Function(...Object.keys(mainScope),methods.markBatch+'\n'+methods.civilianSurface+'\n'+methods.frustum+'\n'+methods.buildCivilian+'\nreturn buildCivilian;')(...Object.values(mainScope));
  const token=value=>{
    if(!value?.isColor)return null;
    const matches=[];
    for(const [slot,hex]of Object.entries(palette))for(const factor of [1,.8,.7,.72,.66,.55]) {
      if(new THREE.Color(hex).multiplyScalar(factor).toArray().every((channel,index)=>Math.abs(channel-value.toArray()[index])<1e-12))
        matches.push({slot,factor});
    }
    if(matches.length>1)throw new Error('Ambiguous civilian palette binding');
    return matches[0]??null;
  };
  const save=(key,root,bindings={})=>{
    finishUnitSurfaces(root);root.updateMatrixWorld(true);outlinify(root,0.08);
    enableDissolve(root);
    root.traverse(node=>{if(node.isMesh){node.castShadow=!node.userData.isOutline&&!node.material.transparent;node.receiveShadow=node.castShadow;}});
    const graph=graphOf(root),encode=value=>value?.isObject3D?{$node:graph.ids.get(value)}:Array.isArray(value)?value.map(encode)
      :value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([name,item])=>[name,encode(item)])):value;
    profiles[key]={bindings:encode(bindings),palette:Object.fromEntries([...graph.materialIds].map(([material,id])=>[id,
      {color:token(material.color),emission:token(material.emissive)}]))};
    graphs[key]=graph.data;disposeTree(root);
  };
  for(const bottoms of [...new Set(options.bottoms)])for(const footwear of [...new Set(options.footwear)])for(const sleeve of ['short','long']) {
    appearance={...appearance,bottoms,footwear,clothing:sleeve==='long'?'coat':'shirt'};
    const root=buildMain('STEEL',0,0),rig=root.userData.rig;
    const surfaces={};root.traverse(node=>{if(['civilian/torso','civilian/pelvis'].includes(node.name))surfaces[node.name.slice(9)]=node;});
    save('main_'+bottoms+'_'+footwear+'_'+sleeve,root,{rig,body:root.children[0],surfaces});
  }
  const segment=(key,apply)=>{
    const root=new THREE.Group(),hips=new THREE.Group(),head=new THREE.Group();root.add(hips,head);
    apply(hips,head);save(key,root,{hips,head});
  };
  for(const hairStyle of [...new Set(options.hairStyle)])for(const facialHair of [...new Set(options.facialHair)])for(const older of [false,true])
    segment('hair_'+hairStyle+'_'+facialHair+'_'+Number(older),(_hips,head)=>helpers.hair(head,{...appearance,hairStyle,facialHair,age:older?55:54}));
  const neutral={...appearance,clothing:'none',bottoms:'none',headwear:'none',accessory:'none'};
  for(const clothing of [...new Set(options.clothing)])segment('clothes_'+clothing,(hips,head)=>helpers.clothes(hips,head,{...neutral,clothing}));
  segment('jeans',(hips,head)=>helpers.clothes(hips,head,{...neutral,bottoms:'jeans'}));
  for(const headwear of [...new Set(options.headwear)])segment('headwear_'+headwear,(hips,head)=>helpers.clothes(hips,head,{...neutral,headwear}));
  for(const accessory of [...new Set(options.accessory)])segment('accessory_'+accessory,(hips,head)=>helpers.clothes(hips,head,{...neutral,accessory}));
  for(const [family,row]of d.CIVILIANS.entries())for(const professional of [false,true])
    segment('profession_'+family+'_'+Number(professional),hips=>helpers.profession(hips,row,appearance.clothColor,
      professional?kits[row.name]:{...kits[row.name],coat:'casual',head:'none'}));
  const rings={};
  for(const side of ['STEEL','SWARM']) {
    const unit=makeUnit('civ',side,{appearanceSeed:0,ring:true}).group;
    const ring=unit.children.find(node=>node.userData.teamRing);
    if(!ring)throw new Error('Missing original civilian team ring');
    rings[side]=ring.geometry.parameters.outerRadius;
    ring.removeFromParent();const root=new THREE.Group();root.add(ring);save('ring_'+side.toLowerCase(),root);
    disposeTree(unit);
  }
  const poses=mesh=>{
    mesh.updateMatrixWorld(true);const rows=[];
    mesh.traverse(node=>{
      if(!node.isMesh||node.userData.isOutline)return;
      const positions=node.geometry.attributes.position,normals=node.geometry.attributes.normal;
      const normalMatrix=new THREE.Matrix3().getNormalMatrix(node.matrixWorld),p=new THREE.Vector3(),n=new THREE.Vector3();
      rows.push({name:node.name,color:node.material.color.getHex(),points:Array.from({length:positions.count},(_,index)=>
        p.fromBufferAttribute(positions,index).applyMatrix4(node.matrixWorld).toArray()),
        normals:normals?Array.from({length:normals.count},(_,index)=>n.fromBufferAttribute(normals,index).applyMatrix3(normalMatrix).normalize().toArray()):[]});
    });return rows;
  };
  const jobs=[0,1,42,123456789,4294967303].flatMap(seed=>d.CIVILIANS.map((_,profession)=>({seed,profession})));
  const categories=['gender','ethnicity','hairStyle','clothing','bottoms','headwear','accessory','footwear','facialHair'];
  const seen=new Set();
  for(let seed=0;seed<5000;seed++) {
    const candidate=generateCivilian(seed,0),labels=categories.map(key=>key+'/'+candidate[key]);
    labels.push('older/'+Number(candidate.age>=55),'main/'+candidate.bottoms+'/'+candidate.footwear+'/'+Number(['jacket','hoodie','sweater','coat'].includes(candidate.clothing)));
    if(labels.some(label=>!seen.has(label)))jobs.push({seed,profession:seed%d.CIVILIANS.length});
    labels.forEach(label=>seen.add(label));
  }
  for(const key of categories)for(const value of new Set(options[key]))if(!seen.has(key+'/'+value))
    throw new Error('Incomplete original civilian appearance coverage: '+key+'/'+value);
  for(const {seed,profession}of [...new Map(jobs.map(job=>[job.seed+'/'+job.profession,job])).values()]) {
    const side=profession%2?'SWARM':'STEEL',mesh=makeUnit('civ',side,{ch:profession,appearanceSeed:seed,ring:true,dissolve:true}).group;
    const dims=measure(THREE,mesh,'civ',{k:'civilian',id:seed,s:side,pf:profession},true,new Map());
    const entity={id:String(seed),mesh,civ:true,hero:false,heroY:0,flies:false},steps=[];
    steps.push({position:[0,0,0],yaw:0,now:10,delta:0,meshes:poses(mesh)});
    for(const input of [{position:[.2,0,.4],yaw:.3,now:10.1,delta:.1},{position:[2,0,3],yaw:1,now:10.3,delta:.2},
      {position:[2,0,3],yaw:-3.13,now:10.5,delta:.2},{position:[2,0,3],yaw:3.13,now:11,delta:.5}]) {
      const previous=mesh.position.clone(),previousYaw=mesh.rotation.y;
      mesh.position.fromArray(input.position);mesh.rotation.y=input.yaw;
      stepCombatFx(entity,input.now,input.delta);stepLocomotion(entity,input.delta,input.now,previous.x,previous.z,previousYaw);
      steps.push({...input,meshes:poses(mesh)});
    }
    fixtures.push({seed,profession,side,appearance:generateCivilian(seed,profession),dimensions:{height:dims.dimH,top:dims.dimTop,radius:dims.dimR,centre:dims.dimTop-dims.dimH/2},steps});
    disposeTree(mesh);
  }
  return {graphs,profiles,rings,fixtures};
}
