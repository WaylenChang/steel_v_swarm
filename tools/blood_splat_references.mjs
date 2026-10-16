// Execute the original client spray, fade and clear methods with an isolated visual random stream.
export function captureBloodSplats({THREE,d,BattleClient}) {
  const previousRandom=Math.random,cases=[];
  const clone=value=>JSON.parse(JSON.stringify(value));
  try {
    for(const pose of [{yaw:0,pitch:0,fov:68,aspect:16/9},{yaw:1.2,pitch:.6,fov:35,aspect:.6},{yaw:-2.8,pitch:-.8,fov:0,aspect:0}]) {
      for(const scenario of ['ordinary','shield','empty','dead','no_side','zero_pool','caps']) {
        let draws=0;const random=[.25,0,.999999,.5,.125,.875,.375,.625];
        Math.random=()=>random[(draws++)%random.length];
        const camera=new THREE.PerspectiveCamera(pose.fov,pose.aspect,.5,4000);
        camera.position.set(12,20,-9);camera.rotation.set(pose.pitch,pose.yaw,.13,'YXZ');camera.updateMatrixWorld(true);
        const calls=[];
        const context={camera,side:scenario==='no_side'?'':'STEEL',dead:scenario==='dead',
          maxHp:scenario==='zero_pool'?0:700,maxSp:scenario==='zero_pool'?0:120,sp:scenario==='empty'?0:120,
          defending:scenario==='shield'||scenario==='empty',_blood:[],_glints:[],_bloodSeq:0,_bloodOn:false,_glintOn:false,
          hud:{blood:list=>calls.push({kind:'blood',list:clone(list)}),glint:list=>calls.push({kind:'glint',list:clone(list)})}};
        const events=[],amounts=scenario==='caps'?Array.from({length:24},(_,index)=>10+index):[-1,0,.001,10,180.4,1000];
        for(const [index,amount]of amounts.entries()) {
          if(scenario==='caps')context.defending=index%2===1;
          const origin=[Math.fround([-50,12,100,12][index%4]),Math.fround(40),Math.fround([-9,-100,-9,100][index%4])];
          const event={x:origin[0],z:-origin[2],v:amount,...(index%2?{ay:origin[1]}:{})};
          BattleClient.prototype._bloodSplat.call(context,event);
          events.push({origin,amount,...(event.ay!=null?{elevation:event.ay}:{}),defending:context.defending});
        }
        const initial={blood:clone(context._blood),glints:clone(context._glints),sequence:context._bloodSeq,draws};
        const steps=[];
        for(const delta of [0,.016,.35,.9,.5,2,0,0]) {
          calls.length=0;
          BattleClient.prototype._updateBlood.call(context,delta);BattleClient.prototype._updateGlint.call(context,delta);
          steps.push({delta,blood:clone(context._blood),glints:clone(context._glints),calls:clone(calls)});
        }
        calls.length=0;BattleClient.prototype._clearBlood.call(context);
        cases.push({pose,scenario,frame:camera.matrixWorld.toArray(),vital:{side:context.side,dead:context.dead,
          max_hp:context.maxHp,max_shield:context.maxSp,shield:context.sp},events,random,initial,steps,
          cleared:{blood:context._blood,glints:context._glints,sequence:context._bloodSeq,calls:clone(calls)}});
      }
    }
  } finally {Math.random=previousRandom;}
  const curves=[];
  for(const left of [-1,0,.000001,.1,.35,.9,1.02,2.4,2.75,10])curves.push({left,blood:d.bloodAlpha(left),glint:d.glintAlpha(left)});
  const positions=[];
  for(const bearing of [-Math.PI,-1,0,.3,Math.PI])for(const elev of [-Math.PI/2,0,Math.PI/2])for(const half of [0,.3,1])
    positions.push({bearing,elev,half,result:d.bloodScreenUv(bearing,elev,half,half)});
  return {bloodSplats:cases,bloodCurves:curves,bloodScreenPositions:positions};
}
