// Capture source shader functions and the original material/ghost lifecycle offline.
export function captureDissolve({THREE,d,toon,BattleClient,sceneDamage,mapBuilding,disposeTree}) {
  if(d.DISSOLVE.FAR_M>0)throw new Error('Distance dissolve requires source DOF integration before enabling it');
  const sample=toon.toonMat(0xffffff,{dissolve:true});
  const shader={uniforms:{},vertexShader:THREE.ShaderLib.toon.vertexShader,fragmentShader:THREE.ShaderLib.toon.fragmentShader};
  sample.onBeforeCompile(shader);
  const take=name=>{
    const start=shader.fragmentShader.indexOf(name),brace=shader.fragmentShader.indexOf('{',start);
    if(start<0||brace<0)throw new Error('Missing original dissolve shader function '+name);
    let depth=1,end=brace+1;
    while(depth&&end<shader.fragmentShader.length) {const c=shader.fragmentShader[end++];if(c==='{')depth++;else if(c==='}')depth--;}
    if(depth)throw new Error('Unclosed original dissolve shader function '+name);
    return shader.fragmentShader.slice(start,end);
  };
  const functions=[take('float celHash('),take('float celNoise('),take('bool celDissolve(')];
  functions[2]=functions[2].replace(/\(\s*vec3 dp\s*\)/,'(vec3 dp, float uDis)');
  if(!functions[2].includes('float uDis)'))throw new Error('Original dissolve signature changed');
  const rules={...d.DISSOLVE,shaderFunctions:functions.join('\n')};sample.dispose();
  const materialCases=[];
  for(const instanced of [false,true])for(const shared of [false,true])for(const grouped of [false,true]) {
    const root=new THREE.Group();root.position.set(12,20,-9);root.rotation.set(.13,.21,-.17);root.scale.set(-1.2,1.7,.9);
    const opaque=toon.toonMat(0x8090a0,{dissolve:true});
    const plain=new THREE.MeshBasicMaterial({color:0x304050});
    const transparent=new THREE.MeshBasicMaterial({color:0xb06030,transparent:true,opacity:.35});
    const materials=[opaque,plain,transparent,shared?opaque:toon.cloneVisualMaterial(opaque)];
    const geometry=new THREE.BoxGeometry(2,6,2),nodes=[];
    for(let i=0;i<materials.length;i++) {
      const node=instanced&&i===3?new THREE.InstancedMesh(geometry,materials[i],2):new THREE.Mesh(geometry,materials[i]);
      node.name='part'+i;node.position.set(i*2,i/3,-i);
      if(node.isInstancedMesh) {
        node.setMatrixAt(0,new THREE.Matrix4().makeTranslation(0,0,0));
        node.setMatrixAt(1,new THREE.Matrix4().makeTranslation(8,4,2));
      }
      nodes.push(node);root.add(node);
    }
    if(grouped)root.add(new THREE.Mesh(geometry,[opaque,opaque,plain,transparent,materials[3]]));
    const outline=new THREE.Mesh(geometry,plain);outline.userData.isOutline=true;outline.name='outline';root.add(outline);
    const steps=[];
    for(const [value,origin]of [[1,[12,20,-9]],[.75,null],[.25,[3,4,5]],[0,null],[-1,null],[2,null],[.4,null]]) {
      const count=toon.setDissolve(root,value,origin?new THREE.Vector3(...origin):null);
      steps.push({value,origin,count,outline:outline.visible,materials:materials.map(m=>({enabled:!!m.userData.celDisU,
        value:m.userData.celDisU?.value??null,origin:m.userData.celDisO?.value.toArray()??null}))});
    }
    materialCases.push({instanced,shared,grouped,steps});disposeTree(root);
  }
  const ghosts=[];
  for(const kind of ['car','relay','civilian','unknown'])for(const neutral of [false,true])for(const collapsed of [false,true])
    for(const visible of [false,true])for(const enabled of [false,true])for(const die of [false,true]) {
      // Non-neutral known profiles use the shared flatten effect, captured separately.
      if(!neutral&&sceneDamage.sceneDamageProfile(kind))continue;
      const scene=new THREE.Scene(),root=new THREE.Group();root.position.set(12,20,-9);root.visible=visible;scene.add(root);
      const surface=enabled?toon.toonMat(0x8090a0,{dissolve:true}):new THREE.MeshStandardMaterial({color:0x8090a0});
      const mesh=new THREE.Mesh(new THREE.BoxGeometry(2,6,2),surface);root.add(mesh);
      const outline=new THREE.Mesh(mesh.geometry,new THREE.MeshBasicMaterial());outline.userData.isOutline=true;root.add(outline);
      const ent={id:42,kind,mesh:root,neutral,collapsed,dmgFx:new THREE.Group()};root.add(ent.dmgFx);
      const bursts=[];let released=0;
      const remove=new Function('releaseLightningScorch','releaseMobileDamage','sceneDamageBurst','sceneDamageProfile','applySceneDamage',
        'MAP_BUILDING','DISSOLVE','setDissolve','disposeTree','return function '+BattleClient.prototype._removeEnt.toString())(
          ()=>{},()=>{released++;},(_scene,_effects,entity,stage)=>bursts.push({id:entity.id,stage}),sceneDamage.sceneDamageProfile,
          ()=>{throw new Error('Unexpected flatten path');},mapBuilding.MAP_BUILDING,d.DISSOLVE,toon.setDissolve,()=>{});
      const update=new Function('dissolveOutAt','setDissolve','releaseMobileDamage','disposeTree','return function '+BattleClient.prototype._updateDissolveGhosts.toString())(
        d.dissolveOutAt,toon.setDissolve,()=>{released++;},()=>{});
      const client={scene,effects:[],ents:new Map([[42,ent]]),damaged:new Set([ent]),spinners:new Map(),flamers:new Map(),
        _dissolveGhosts:[],_unregisterViewOccluders(){}};
      const capture=()=>({attached:root.parent===scene,visible:root.visible,ghosts:client._dissolveGhosts.length,
        time:client._dissolveGhosts[0]?.t??null,value:surface.userData.celDisU?.value??null,
        origin:surface.userData.celDisO?.value.toArray()??null,outline:outline.visible,bursts:bursts.slice()});
      remove.call(client,42,ent,die);const initial=capture(),frames=[];
      for(const delta of [0,.016,0,.12,.2,.1,.014,.1]) {update.call(client,delta);frames.push({delta,...capture()});}
      ghosts.push({kind,neutral,collapsed,visible,enabled,die,initial,frames});disposeTree(root);
    }
  const clocks=[-.1,0,.016,.1,.2,.3,.449999,.45,.450001,1].map(time=>({time,value:d.dissolveOutAt(time)}));
  return {rules,fixtures:{dissolveMaterials:materialCases,dissolveGhosts:ghosts,dissolveClocks:clocks}};
}
