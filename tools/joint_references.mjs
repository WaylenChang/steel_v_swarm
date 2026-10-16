import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { quaternionReferences } from './quaternion_references.mjs';

export async function jointReferences(gait, source, motionText, lerpFPS) {
  const [{grabFn,grabConst,grabBlock},THREE] = await Promise.all([
    import(pathToFileURL(join(source,'tools/audit_src.mjs')).href), import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href),
  ]);
  const quaternions=quaternionReferences(THREE);
  const thresholds = [...THREE.Euler.prototype.setFromRotationMatrix.toString().matchAll(/Math\.abs\(\s*m\d\d\s*\)\s*<\s*([\d.]+)/g)].map(match=>Number(match[1]));
  if(thresholds.length!==6 || new Set(thresholds).size!==1) throw new Error('Original Euler gimbal thresholds diverged');
  const idle = /const idleOf = [^;]+;/.exec(motionText)?.[0];
  const idleNumber = /1 - a \/ ([\d.]+)/.exec(idle||'');
  if(!idleNumber)throw new Error('Missing original idle amplitude');
  const scope={GAIT_ANAT:true,cycleU:gait.cycleU,limbFlex:gait.limbFlex,lerpFPS};
  const arrow=name=>{
    const marker='const '+name+' =',start=motionText.indexOf(marker),brace=motionText.indexOf('{',start);
    if(start<0||brace<start)throw new Error('Missing original joint helper: '+name);
    return motionText.slice(start,brace)+grabBlock(motionText,marker)+';';
  };
  const methods = new Function(...Object.keys(scope), `${grabConst(motionText,'S0')}
    ${arrow('gsig')} ${arrow('fsig')}
    ${/const clamp = [^;]+;/.exec(motionText)[0]} ${/const damp = [^;]+;/.exec(motionText)[0]} ${idle}
    ${grabFn(motionText,'flexChain')} ${grabFn(motionText,'gunPitch')} ${grabFn(motionText,'stabilizeHead')}
    ${grabFn(motionText,'whipTail')}
    ${grabFn(motionText,'poseFlightWing')}
    ${grabFn(motionText,'softLeg')} ${grabFn(motionText,'tentGuard')}
    return {flexChain,gunPitch,stabilizeHead,whipTail,poseFlightWing,softLeg,tentGuard,gsig,fsig,idleOf};`)(...Object.values(scope));
  const record = node=>({p:node.position.toArray(),q:node.quaternion.toArray(),s:node.scale.toArray(),r:[node.rotation.x,node.rotation.y,node.rotation.z],order:node.rotation.order});
  const make = (order='XYZ')=>{
    const node=new THREE.Object3D();node.rotation.order=order;node.rotation.set(.12,.3,-.6);node.scale.set(-1,2,1);return node;
  };
  const eulerSamples=[],bodyRotations=[];
  for(const order of ['XYZ','XZY','YXZ','YZX','ZXY','ZYX']) {
    for(const angles of [[.12,.3,-.6],[Math.PI/2,0,0],[0,Math.PI/2,0],[0,0,Math.PI/2],[1.5704,-1.5704,.7]]) {
      // Isolate the source callback with exactly the quaternion values held by native Quaternion.
      const q=new THREE.Quaternion().setFromEuler(new THREE.Euler(...angles,order)).toArray().map(Math.fround);
      const e=new THREE.Euler().setFromQuaternion(new THREE.Quaternion(...q),order);
      eulerSamples.push({order,q,result:[e.x,e.y,e.z]});
    }
    const node=make(order),initial=record(node),steps=[];
    for(const input of [{axis:'y',value:8.4},{scale:[.001,.001,.001]},{position:[.3,-.4,.7]},
      {quaternion:new THREE.Quaternion().setFromEuler(new THREE.Euler(.7,-.3,.2,order)).toArray().map(Math.fround)},
      {axis:'x',value:14.3},{scale:[0,0,0]},{position:[1,2,3]},{axis:'z',value:1.1},{scale:[-1,2,1]}]) {
      if(input.axis)node.rotation[input.axis]=input.value;
      if(input.scale)node.scale.fromArray(input.scale);
      if(input.position)node.position.fromArray(input.position);
      if(input.quaternion)node.quaternion.fromArray(input.quaternion);
      steps.push({...input,result:record(node)});
    }
    bodyRotations.push({initial,steps});
  }
  const bodyFlex=[];
  const profiles=[null,{P:gait.limbProfile({}).hind,duty:.62},{P:gait.limbProfile({fore:'unguligrade'}).fore,duty:.3},
    {P:gait.limbProfile({hind:'plantigrade'}).hind,P2:{...gait.limbProfile({hind:'plantigrade'}).hind,role:'human'},mix:.6,duty:.4}];
  for(const anatomy of profiles)for(const order of ['XYZ','YXZ'])for(const amplitude of [-.1,0,.5,1.5]) {
    const chain=Array.from({length:5},(_,index)=>({g:make(order),base:.1*index,k:index%2?-1:1,d:.17*index,axis:['x','y','z'][index%3]}));
    const initial=chain.map(j=>record(j.g)),spec=chain.map(({g,...row})=>row),steps=[];
    for(const input of [{phase:-Math.PI/2,now:0,idle:1,load:.45,hold:0},{phase:.7,now:.016,idle:.5,load:.1,hold:.35},
      {phase:7,now:3,idle:0,load:.6,hold:.1}]) {
      methods.flexChain(chain,input.phase,amplitude,input.idle,input.now,input.load,input.hold,anatomy);
      steps.push({...input,result:chain.map(j=>record(j.g))});
    }
    bodyFlex.push({anatomy,order,amplitude,initial,spec,steps});
  }
  const bodySignatures=[null,{},...[-1,0,.5,1,2].map(poise=>({poise})),
    {poise:null,idleF:0,idleA:0,launch:0,spool:0,brake:0,settle:0,hover:0,hoverF:0,hoverA:0,surge:0,flare:0,bank:0},
    {poise:.2,idleF:1.3,idleA:.7,launch:.8,spool:.5,brake:.6,settle:1.2,hover:.4,hoverF:.8,hoverA:1.1,surge:.7,flare:.2,bank:1.3}]
    .map(spec=>({spec,ground:methods.gsig({moveSig:spec}),flight:methods.fsig({moveSig:spec})}));
  const bodyIdle=[-.1,0,.03,.06,.5,2].map(amplitude=>({amplitude,result:methods.idleOf(amplitude)}));
  const bodyGuns=[];
  for(const gun of [null,0,.05,-.2])for(const aiming of [0,.4,1])for(const kick of [0,1.3]) {
    const node=make('YXZ'),initial=record(node),pivot={g:node,rest:.2,aim:-.4};
    methods.gunPitch(pivot,aiming,kick,-.7,{gun});bodyGuns.push({initial,gun,aiming,kick,charge:-.7,rest:.2,aim:-.4,result:record(node)});
  }
  const bodyHeads=[];
  for(const neck of [false,true])for(const idle of [0,1])for(const strength of [.85,0,1]) {
    const head=make(),joint=neck?make():null,initial={head:record(head),neck:joint?record(joint):null};
    methods.stabilizeHead({head,neck:joint},[.2,-.5,.1],idle,3,strength,.6);
    bodyHeads.push({initial,accumulated:[.2,-.5,.1],idle,now:3,strength,scan:.6,result:{head:record(head),neck:joint?record(joint):null}});
  }
  const bodyTails=[];
  for(const aim of [null,{p:0,rot0:-.5,rotD:.2},{p:.4,rot0:-.5,rotD:.2},{p:2,rot0:-.5,rotD:.2}])
    for(const curl of [null,{rot0:.12,rotD:-.09}]) for(const stiffness of [0,.6,1]) for(const sway of [null,
      {frequency:.8,delay:.4,idle:.05,travel:.2,pitch:-.1,pitchWave:.08}]) {
      const segments=Array.from({length:3},()=>make('YXZ')),initial=segments.map(record),state={ph:1.23},steps=[];
      for(const input of [{delta:0,phase:1.23,amplitude:0,idle:1,now:0,yawRate:0},
        {delta:.016,phase:2.1,amplitude:.6,idle:.2,now:.016,yawRate:4},
        {delta:.2,phase:5.7,amplitude:1.2,idle:0,now:.216,yawRate:-4},
        {delta:2,phase:5.7,amplitude:0,idle:1,now:2.216,yawRate:0}]) {
        state.ph=input.phase;
        methods.whipTail(segments,state,input.delta,input.amplitude,input.idle,input.now,input.yawRate,.13,aim,curl,stiffness,sway);
        steps.push({...input,state:{...state},result:segments.map(record)});
      }
      bodyTails.push({initial,aim,curl,stiffness,sway,base:.13,steps});
    }
  const bodyWings=[];
  for(const hand of [false,true]) for(const membrane of [false,true]) for(const sgn of [-1,1]) for(const additive of [false,true]) {
    const nodes={w:make('YXZ'),outer:make('XYZ'),hand:hand?make('ZXY'):null};
    const initial=Object.fromEntries(Object.entries(nodes).map(([key,node])=>[key,node?record(node):null]));
    const spec={sgn,membrane,dihedral:.2,elbowSweep:-.1,wristSweep:.15},steps=[];
    for(const input of [{phase:0,amplitude:0,attack:0},{phase:.7,amplitude:.6,attack:.4},{phase:3.2,amplitude:1.1,attack:1}]) {
      methods.poseFlightWing({...nodes,...spec},input.phase,input.amplitude,input.attack,additive);
      steps.push({...input,result:Object.fromEntries(Object.entries(nodes).map(([key,node])=>[key,node?record(node):null]))});
    }
    bodyWings.push({initial,spec,additive,steps});
  }
  const bodySoftLimbs=[];
  for(const count of [1,4]) for(const method of ['softLeg','tentGuard']) {
    const chain=Array.from({length:count},(_,index)=>({g:make('YXZ'),base:.1*index,k:index%2?-1:1,d:.3*index}));
    const initial=chain.map(joint=>record(joint.g)),spec=chain.map(({g,...joint})=>joint),steps=[];
    for(const input of [{phase:0,amplitude:0,now:0,quest:0,index:0},{phase:2.3,amplitude:1.4,now:.3,quest:.4,index:1},
      {phase:5.7,amplitude:.2,now:2,quest:.1,index:3}]) {
      if(method==='softLeg')methods.softLeg(chain,input.phase,input.amplitude,input.now,input.quest);
      else methods.tentGuard(chain,input.now,input.index,input.phase,input.amplitude);
      steps.push({...input,result:chain.map(joint=>record(joint.g))});
    }
    bodySoftLimbs.push({method,initial,spec,steps});
  }
  return {rotation:{gimbal:thresholds[0],numberEpsilon:quaternions.numberEpsilon},idleAmplitude:Number(idleNumber[1]),
    fixtures:{...quaternions.fixtures,eulerSamples,bodyRotations,bodyFlex,bodySignatures,bodyIdle,bodyGuns,bodyHeads,bodyTails,bodyWings,bodySoftLimbs}};
}
