// Original constructor and closures provide texture, geometry, random order and animation references.
export function captureDamageFx({THREE,fx,sceneDamage,BattleClient,flameGeometry,graphOf,disposeTree}) {
  const previous=Math.random,random=[.125,.875,.375,.625,0,.999,.25,.75,.5];
  const damageFxFrames=[],damageFxStages=[],graphs={},textures={};
  let weather={windAmp:1,windDir:[1,0]};
  try {
    Math.random=()=>.5;
    const template=fx.makeDamageFx({r:2,top:3,h:3});
    const smokeTexture=template.children[0].material.map,crackTexture=template.children[4].material.map;
    textures['damage-smoke']=smokeTexture.image.toDataURL('image/png').split(',')[1];
    textures['damage-crack']=crackTexture.image.toDataURL('image/png').split(',')[1];
    const plane=template.children[4].material;
    const canvas=document.createElement('canvas'),gl=canvas.getContext('webgl2',{depth:true});
    if(!gl)throw new Error('Damage crack depth capture requires original WebGL2 support');
    const depthBits=gl.getParameter(gl.DEPTH_BITS);
    if(!(depthBits>0))throw new Error('Missing source depth-buffer precision');
    gl.getExtension('WEBGL_lose_context')?.loseContext();
    const rules={polygonOffsetFactor:plane.polygonOffsetFactor,polygonOffsetUnits:plane.polygonOffsetUnits,depthBits};
    disposeTree(template);
    const mesh=new THREE.Mesh(flameGeometry(.5,1),new THREE.MeshBasicMaterial({color:0xffffff}));
    graphs.damage_flame_unit=graphOf(mesh).data;disposeTree(mesh);
    const make=new Function('THREE','smokeTexture','crackTexture','flameGeometry','glowTexture','getWeatherDynamics',
      'return '+fx.makeDamageFx.toString())(THREE,()=>smokeTexture,()=>crackTexture,flameGeometry,fx.glowTexture,()=>weather);
    for(const dimensions of [{radius:0,top:0,height:1},{radius:2,top:5,height:6},{radius:40,top:100,height:80}])
      for(const fire of [false,true])for(const surfaceCracks of [false,true])for(const mirrored of [false,true]) {
        let draws=0;Math.random=()=>random[(draws++)%random.length];
        const parent=new THREE.Group();parent.position.set(12,20,-9);parent.rotation.set(.17,-.6,.08,'YXZ');
        parent.scale.set(mirrored?-1.2:1.2,.8,1.1);
        const group=make({r:dimensions.radius,top:dimensions.top,h:dimensions.height,fire,surfaceCracks});parent.add(group);
        const capture=()=>{
          parent.updateMatrixWorld(true);
          return {stage:group.userData.stage,nodes:group.children.map(node=>({position:node.position.toArray(),scale:node.scale.toArray(),
            quaternion:node.quaternion.toArray(),visible:node.visible,opacity:node.material.opacity,color:node.material.color.toArray(),
            phase:node.userData.ph??null,geometry:node.geometry?.attributes.position?Array.from(node.geometry.attributes.position.array):null,
            normals:node.geometry?.attributes.normal?Array.from(node.geometry.attributes.normal.array):null,
            width:node.geometry?.parameters?.width??null,height:node.geometry?.parameters?.height??null}))};
        };
        const initial=capture(),steps=[];
        const frames=[{dt:0,now:0,stage:1,amp:0},{dt:.016,now:.016,stage:1,amp:.5},{dt:.12,now:.2,stage:2,amp:2},
          {dt:0,now:.35,stage:2,amp:3},{dt:.4,now:1,stage:2,amp:-1},{dt:1.7,now:100.1,stage:2,amp:1},
          {dt:.1,now:100.2,stage:1,amp:2},{dt:.2,now:100.4,stage:2,amp:2}];
        for(const frame of frames) {
          weather={windAmp:frame.amp,windDir:[.6,-.8]};
          group.userData.setStage(frame.stage);group.userData.update(frame.dt,frame.now);
          steps.push({...frame,weather,result:capture()});
        }
        damageFxFrames.push({dimensions,fire,surfaceCracks,mirrored,parent:parent.matrix.toArray(),random,draws,initial,steps});
        disposeTree(parent);
      }
    let allocated=0,released=0,options=[];
    const update=new Function('DMG_FX','sceneDamageProfile','makeDamageFx','disposeTree','return function '+BattleClient.prototype._updateDamageStage.toString())(
      fx.DMG_FX,sceneDamage.sceneDamageProfile,settings=>{
        allocated++;options.push(settings);const group=new THREE.Group();group.userData.setStage=stage=>{group.userData.stage=stage;};return group;
      },()=>released++);
    for(const settings of [{kind:'robot'},{kind:'soldier'},{kind:'hyper'},{kind:'car',neutral:true},{kind:'unknown'},
      {kind:'unknown',neutral:true},{kind:'robot',isSelf:true},{kind:'civilian',civ:true},{kind:'decoy',decoy:true},{kind:'kami',kami:true}]) {
      allocated=0;released=0;options=[];
      const ent={...settings,hp:100,max:100,dead:false,mesh:new THREE.Group(),dimR:0,dimTop:0,dimH:0};
      const client={damaged:new Set()},steps=[];
      for(const values of [{hp:100},{hp:50},{hp:50},{hp:25},{hp:26},{hp:0,dead:true},{hp:20,dead:false},
        {max:0},{max:'NAN'},{max:'INF'},{max:'-INF'},{max:100,isSelf:true},{isSelf:false},{hp:100},{hp:25},
        {collapsed:true},{collapsed:false},{hp:'NAN'},{hp:'INF'},{hp:'-INF'},{hp:100}]) {
        const numeric=value=>value==='NAN'?NaN:value==='INF'?Infinity:value==='-INF'?-Infinity:value;
        Object.assign(ent,Object.fromEntries(Object.entries(values).map(([key,value])=>[key,numeric(value)])));update.call(client,ent);
        steps.push({values,stage:ent.dmgStage??0,present:!!ent.dmgFx,fxStage:ent.dmgFx?.userData.stage??null,
          active:client.damaged.has(ent),allocated,released,options:options.slice()});
      }
      damageFxStages.push({settings,steps});
    }
    return {graphs,textures,rules,fixtures:{damageFxFrames,damageFxStages}};
  } finally {Math.random=previous;}
}
