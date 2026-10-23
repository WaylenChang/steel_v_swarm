export async function captureVitalBars(page, methods) {
  return page.evaluate(async methods=>{
    const THREE=await import('three'),d=await import('/js/data.js');
    const {sceneDamageProfile}=await import('/js/sceneDamage.js');
    const Client=new Function('THREE','sceneDamageProfile','bossSegN','bossSegFill','bossGlow','bossSegFrac',
      'return class {\n'+methods.join('\n')+'\n};')(THREE,sceneDamageProfile,d.bossSegN,d.bossSegFill,d.bossGlow,d.bossSegFrac);
    const snapshot=ent=>ent.bar?{y:ent.bar.position.y,width:ent.barW,nodes:ent.bar.children.map(node=>({
      size:[node.geometry.parameters.width,node.geometry.parameters.height],position:node.position.toArray(),scale:node.scale.toArray(),
      colour:'#'+node.material.color.getHexString(),opacity:node.material.opacity,visible:node.visible,order:node.renderOrder,
      depthTest:node.material.depthTest,depthWrite:node.material.depthWrite,side:node.material.side})),
      fills:(ent.barFills||[]).map(node=>ent.bar.children.indexOf(node)),shield:ent.bar.children.indexOf(ent.barSfg),
      glow:ent.bar.children.indexOf(ent.barGlow),frame:ent.bar.children.indexOf(ent.barFrame),sceneFill:ent.bar.children.indexOf(ent.barFg)}:null;
    const templates={},programs=[];
    const create=options=>({mesh:new THREE.Group(),hp:50,max:100,sp:50,maxSp:100,dimTop:9,side:'SWARM',kind:'robot',
      isStatic:false,isSelf:false,civ:false,neutral:false,collapsed:false,colH:7,...options});
    for(const staticBar of [false,true])for(const shield of [false,true])for(const boss of [false,true]) {
      const client=new Client();client.side='STEEL';
      const ent=create({isStatic:staticBar,maxSp:shield?100:0,bossSeg:boss?0:null});
      client._updateHpBar(ent);
      const key=(boss?'boss':'regular')+'_'+Number(staticBar)+'_'+Number(shield);
      templates[key]=snapshot(ent);templates[key].offset=templates[key].y-ent.dimTop;
    }
    const sceneClient=new Client();sceneClient.side='STEEL';
    const scene=create({kind:'car',neutral:true,colH:7});sceneClient._updateHpBar(scene);
    templates.scene=snapshot(scene);templates.scene.offset=templates.scene.y-scene.colH;
    const profiles=[
      {name:'ordinary',options:{}},{name:'static',options:{isStatic:true,kind:'tower'}},
      {name:'no-shield',options:{maxSp:0}},{name:'boss',options:{bossSeg:0}},
      {name:'civilian',options:{civ:true,neutral:true,kind:'civilian',side:null,maxSp:0}},
      {name:'scene',options:{kind:'car',neutral:true,maxSp:0}},{name:'ground',options:{kind:'fire',neutral:true,maxSp:0}},
      {name:'self',options:{isSelf:true}},
    ];
    for(const profile of profiles) {
      const client=new Client();client.side='STEEL';
      const ent=create({...profile.options,hp:100,sp:100}),frames=[];
      for(const change of [{hp:100,sp:100},{hp:100,sp:0},{hp:50,sp:35},{hp:100,sp:100},{hp:150,sp:120},
        {hp:0,sp:0},{hp:-1,sp:-3},{hp:70,sp:0,viewer:'SWARM'},{bossSeg:profile.name==='boss'?2:null,hp:25},
        {maxSp:0,hp:50},{maxSp:100,sp:50,hp:25},{collapsed:true,hp:0}]) {
        const {viewer,...state}=change;Object.assign(ent,state);if(viewer)client.side=viewer;
        client._updateHpBar(ent);
        frames.push({state:{hp:ent.hp,max:ent.max,sp:ent.sp,maxSp:ent.maxSp,bossSeg:ent.bossSeg??null,
          collapsed:ent.collapsed,viewer:client.side},bar:snapshot(ent)});
      }
      programs.push({name:profile.name,options:profile.options,frames});
    }
    const minimum=/Math.max\(([\d.]+), frac\)/.exec(methods[0]);
    const sceneDefault=/\(ent.colH \|\| ([\d.]+)\)/.exec(methods[1]);
    const perturbation=/_z\.z \+= ([\d.]+)/.exec(THREE.Matrix4.prototype.lookAt.toString());
    if(!minimum||!sceneDefault||!perturbation||!templates.scene)throw new Error('Missing original overhead vital-bar seams');
    const client=new Client();client.side='SWARM';const ally=create();client._updateHpBar(ally);
    const poses=[];
    for(const scale of [[1,1,1],[2,.6,1.4]])for(const rotation of [[0,0,0],[.2,1.3,-.4]])for(const offset of [[0,0,0],[0,10,0],[0,-10,0],[10,3,-20]]) {
      const client=new Client();client.side='STEEL';const ent=create();client._updateHpBar(ent);
      ent.mesh.position.set(17,5,-11);ent.mesh.rotation.set(...rotation,'XYZ');ent.mesh.scale.set(...scale);ent.mesh.updateMatrixWorld(true);
      const camera=ent.bar.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(...offset));
      ent.bar.lookAt(camera);
      poses.push({position:ent.mesh.position.toArray(),rotation:ent.mesh.quaternion.toArray(),scale,offset,camera:camera.toArray(),bar:ent.bar.quaternion.toArray()});
    }
    return {templates,minimum:Number(minimum[1]),sceneDefault:Number(sceneDefault[1]),parallelPerturbation:Number(perturbation[1]),
      ally:'#'+ally.barFills[0].material.color.getHexString(),foe:templates.regular_0_1.nodes[templates.regular_0_1.fills[0]].colour,programs,poses};
  },methods);
}
