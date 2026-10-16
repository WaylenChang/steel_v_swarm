// Execute the actual death initializer tail and complete camera update method offline.
export function captureDeathSequences({THREE,d,BattleClient}) {
  const initializeSource=BattleClient.prototype._onSelfDeath.toString();
  const start=initializeSource.indexOf('    const fly = this._flying();');
  if(start<0)throw new Error('Missing original death-camera initializer seam');
  const cases=[],random=[.125,.875,.375,.625,.25,.75,0,.999999];
  const previous=Math.random;
  let calls=[];
  const record=(type,point,settings={})=>calls.push({type,...(point?{point:[...point]}:{}),...settings});
  const scope={THREE,frictionFPS:d.frictionFPS,lerpFPS:d.lerpFPS,sideInfo:()=>({color:0x4fc3f7}),
    starburst:(_scene,_effects,x,y,z,radius,color)=>record('spark',[x,y,z],{radius,color}),
    shockRing:(_scene,_effects,x,y,z,radius,color)=>record('shock',[x,y,z],{radius,color}),
    debrisBurst:(_scene,_effects,x,y,z,opts)=>record('mechanical',[x,y,z],{big:!!opts.big,accent:opts.accent}),
    comicPop:(_scene,_effects,x,y,z,opts)=>record('comic',[x,y,z],{big:!!opts.big,hue:opts.hue})};
  const initialize=new Function(...Object.keys(scope),initializeSource.slice(start,initializeSource.lastIndexOf('}')));
  const update=new Function(...Object.keys(scope),'return function '+BattleClient.prototype._updateDeathSeq.toString())(...Object.values(scope));
  const respawnSource=BattleClient.prototype._onSelfRespawn.toString(),respawnEnd=respawnSource.indexOf('    if (isSuperSide');
  if(respawnEnd<0)throw new Error('Missing original death-cinematic respawn cancellation seam');
  const respawn=new Function(respawnSource.slice(respawnSource.indexOf('{')+1,respawnEnd));
  const snapshot=client=>{
    const s=client._deathSeq;
    client.camera.updateMatrixWorld(true);
    return {frame:client.camera.matrixWorld.toArray(),state:s?{t:s.t,dur:s.dur,fly:s.fly,col:s.col,eye:s.eye.toArray(),surf:s.surf,g:s.g,
      p:s.p.toArray(),v:s.v?.toArray()??null,spin:s.spin?.toArray()??null,yaw:s.yaw,pitch:s.pitch,roll:s.roll,
      smokeAcc:s.smokeAcc,climax:s.climax,holdUntil:s.holdUntil,fpvAcc:s.fpvAcc??0,cut:!!s.cut}:null};
  };
  try {
    for(const flying of [false,true])for(const height of [.2,5,50,5000])for(const deferred of [false,true])for(const cancel of [false,true]) {
      let draws=0,pendingCut=null,stop=0;calls=[];
      Math.random=()=>random[(draws++)%random.length];
      const position=[12,20,-9].map(Math.fround),eye=[12,20+height,-9].map(Math.fround),velocity=[30,8,-12].map(Math.fround),angles=[.17,-.6,.08].map(Math.fround);
      const camera=new THREE.PerspectiveCamera();camera.position.fromArray(eye);
      camera.rotation.set(angles[0]+.03,angles[1]-.02,angles[2]+.01,'YXZ');camera.updateMatrixWorld(true);
      const queries=[];
      const surface=(x,z,y)=>{queries.push([x,y,z]);return 20+Math.max(0,x-15)*.04;};
      const client={camera,scene:{},effects:[],pos:new THREE.Vector3(...position),vel:new THREE.Vector3(...velocity),
        yaw:angles[1],pitch:angles[0],roll:angles[2],side:'STEEL',_flying:()=>flying,_surf:surface,
        hud:{deathCine:(on,flash=false)=>record('alert',null,{on:!!on,flash:!!flash})},
        _explosion:(x,y,z,radius,color)=>record('explosion',[x,y,z],{radius,color}),
        _deathPlume:(x,y,z)=>record('plume',[x,y,z]),
        _emberBurst:(x,y,z,count,spread)=>record('embers',[x,y,z],{count,spread}),
        _crashSmoke:(x,y,z,size)=>record('smoke',[x,y,z],{size}),
        _engulfFPV(cam){cam.updateMatrixWorld(true);record('engulf',null,{frame:cam.matrixWorld.toArray()});},
        _wipeCut(callback,color){record('cut',null,{color});if(deferred)pendingCut=callback;else callback();}};
      Object.defineProperty(client,'_hitstop',{get:()=>stop,set:value=>{stop=value;record('hitstop',null,{seconds:value});}});
      const input={position,eye:camera.matrixWorld.toArray(),velocity,angles,flying,color:0x4fc3f7};
      initialize.call(client,...Object.values(scope));
      const initial={...snapshot(client),calls:structuredClone(calls),queries:structuredClone(queries),draws};
      const steps=[];
      for(let index=0;index<40;index++) {
        calls=[];queries.length=0;
        const delta=[0,.016,.06,.12,.003999,.2,.1,.08][index%8];
        const action=cancel&&index===4?'respawn':pendingCut&&index===33?'cut':'step';
        if(action==='respawn')respawn.call(client);
        else if(action==='cut'){const callback=pendingCut;pendingCut=null;callback();}
        else if(client._deathSeq)update.call(client,delta,10+index*.1);
        steps.push({delta,action,...snapshot(client),calls:structuredClone(calls),queries:structuredClone(queries),draws});
      }
      cases.push({input,random,deferred,initial,steps});
    }
  } finally {Math.random=previous;}
  return {deathSequences:cases};
}
