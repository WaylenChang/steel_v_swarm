// Execute only during the final offline content import, against the shipped source.
export function captureBodyFrames({key,create,graphOf,snapshot,unitMotion,combatAsset,stepLocomotion,stepCombatFx,BattleClient,castRemote,cameraProfile,entityState,disposeTree,d}) {
  const result={reference:null,locomotion:null,events:null,authority:null};
  const initialize=()=>{
    const model=create(),graph=graphOf(model),before=new Map();snapshot(graph,before,true);
    const forms=model.userData.morph?{ground:model.userData.morph.ground,air:model.userData.morph.air}:{ground:model.userData.rig};
    const phases=Object.fromEntries([...graph.materialIds].filter(([material])=>material.uniforms?.uTime)
      .map(([material,id])=>[id,material.uniforms.uTime.value]));
    return {model,graph,before,forms,phases};
  };
  const stateOf=forms=>Object.fromEntries(Object.entries(forms).map(([form,rig])=>[form,{
    fields:Object.fromEntries(['_bowAim'].filter(field=>field in rig).map(field=>[field,rig[field]])),
    shield:rig.shield?{phase:rig.shield.phase,posture:rig.shield.posture??null,expand:rig.shield.expand??null,
      state:rig.shield.state?{...rig.shield.state}:null}:null
  }]));
  const uniforms=graph=>[...graph.materialIds].filter(([material])=>material.uniforms?.uTime).map(([material,id])=>
    ({id,time:material.uniforms.uTime.value,flash:material.uniforms.uFlash.value}));
  const {model,graph,before,forms,phases}=initialize();
  if(Object.values(forms).some(rig=>rig.referenceMotion)) {
    const steps=[],entity={};
    const inputs=[{now:10,delta:0},{now:10,delta:-1},{now:10,delta:.016},
      {now:10.01,delta:.01,shot:{slot:'light',t0:10.01},fields:{_kickR:.45,_fireAim:.8,_aimSlot:'light'}},
      {now:10.08,delta:.07},{now:10.1,delta:.02,shot:{slot:'heavy',t0:10.1},fields:{_kickL:1,_chg:.7,_aimH:.8}},
      {now:10.2,delta:.1,fields:{_chg:-.5,_aimH:0}},
      ...['atk','def'].flatMap(slot=>[0,.5,.999999,1,-.01].map(age=>({now:12,delta:.1,cast:{slot,t0:12-age*(forms.ground.combat?.clips[slot]?.duration??(slot==='atk'?1.35:.95))}}))),
      {now:13,delta:.2,cast:null,entity:{df:1,sp:0}},
      {now:13.2,delta:.2,entity:{df:2,sp:null}},
      {now:13.4,delta:.2,entity:{isSelf:true,visualDefense:false,visualShieldExpand:false}},
      {now:13.6,delta:.2,entity:{visualDefense:true,visualShieldExpand:true}},
      {now:15,delta:2,entity:{dead:true}},{now:16,delta:1,entity:{dead:false,isSelf:false,df:0}},
      {now:16.1,delta:.1,invalidNow:'NaN'},{now:16.2,delta:.1,invalidDelta:'Infinity'}];
    if(forms.air)inputs.push({now:17,delta:.1,form:'air',entity:{df:2},fields:{_chg:1,_fireAim:1}},
      {now:17.1,delta:.1,form:'ground',fields:{_chg:0,_fireAim:0}},
      {now:19,delta:2,fields:{_chg:1},entity:{df:2},obstruct:true},
      {now:19.1,delta:.1,fields:{_chg:0},entity:{df:0},obstruct:true});
    let active='ground';
    for(const input of inputs) {
      if(input.form){active=input.form;model.userData.rig=forms[active];
        model.userData.morph.gg.visible=active==='ground';model.userData.morph.ag.visible=active==='air';}
      Object.assign(entity,input.entity||{});if('cast'in input)entity.castFx=input.cast;
      if(input.shot){entity.fireFx=input.shot;for(const owner of Object.values(forms))unitMotion.fireReferenceWeapon(owner,input.shot);}
      for(const owner of Object.values(forms))Object.assign(owner,input.fields||{});
      for(const owner of Object.values(forms))unitMotion.resetReferenceShieldPose(owner.shield);
      if(forms.air)unitMotion.resetReferenceMotion(forms[active==='ground'?'air':'ground']);
      const updates=[];
      if(input.obstruct)for(const owner of Object.values(forms))for(const {node}of owner.combat?.hull.slice(0,1)||[]) {
        node.position.z+=8;node.rotation.y+=.7;updates.push({id:graph.ids.get(node),position:node.position.toArray(),rotation:[node.rotation.x,node.rotation.y,node.rotation.z]});
      }
      unitMotion.stepReferenceMotion(forms[active],entity,input.invalidDelta?Infinity:input.delta,input.invalidNow?NaN:input.now,!forms.air);
      if(forms.air)for(const owner of Object.values(forms)){
        unitMotion.poseReferenceShield(owner.shield,.6);combatAsset.stepAuthoredCombat(owner,entity,input.invalidNow?NaN:input.now);
        combatAsset.clearMorphCombatShield(owner);
      }
      model.updateMatrixWorld(true);
      steps.push({...input,active,updates,states:stateOf(forms),uniforms:uniforms(graph),nodes:snapshot(graph,before,true)});
    }
    result.reference={key,phases,steps};
  }
  disposeTree(model);
  for(const self of cameraProfile?[false,true]:[false]) {
    const {model,graph,before,forms,phases}=initialize();
    const initialState={hero:true,heroY:0,flies:false,df:0,sp:100,...entityState};
    const entity={id:'body/'+key,mesh:model,...initialState,isSelf:self},steps=[];
    const inputs=[{now:20,delta:.003999,move:[0,0,0],yaw:0},
      {now:20.01,delta:.004,move:[.001,0,.002],yaw:.01},
      {now:20.03,delta:.02,move:[.02,0,.1],yaw:.03},
      {now:20.06,delta:.03,move:[.03,0,.2],yaw:.05,shot:{slot:'light',t0:20.06}},
      {now:20.09,delta:.03,move:[.02,0,.2],yaw:.08,shot:{slot:'light',t0:20.09}},
      {now:20.3,delta:.21,move:[.2,.5,.6],yaw:.4,entity:{heroY:.5},cast:{slot:'atk',t0:20.2}},
      {now:20.4,delta:.1,move:[.1,1,.3],yaw:.45,entity:{heroY:2},heavy:{phase:'charge',t0:20.1}},
      {now:20.8,delta:.4,move:[.5,4,1],yaw:.8,entity:{heroY:d.MORPH.GROUND_Y+1,flies:true},cast:null},
      {now:20.9,delta:.1,move:[-.2,2,-.5],yaw:-.3,shot:{slot:'heavy',t0:20.9},heavy:{phase:'fire',t0:20.9}},
      {now:21,delta:.1,move:[0,-2,0],yaw:-3.13,entity:{df:2}},
      {now:21.1,delta:.1,move:[0,-2,0],yaw:3.13,entity:{isSelf:true,visualDefense:true,visualShieldExpand:true}},
      {now:21.6,delta:.5,move:[0,-1.5,0],yaw:3.13,entity:{heroY:0,flies:false,visualDefense:false},cast:{slot:'def',t0:21.5}},
      {now:22,delta:.4,move:[0,0,0],yaw:3.13,entity:{dead:true}},
      {now:23,delta:1,move:[0,0,0],yaw:0,entity:{dead:false,isSelf:false,df:0},cast:null},
      {now:24,delta:1,move:[0,0,0],yaw:0},{now:25,delta:1,move:[0,0,0],yaw:0}];
    if(self)inputs.unshift({now:19.9,delta:.1,move:[.2,0,.3],yaw:1.1,firstPerson:true,shot:{slot:'light',t0:19.9}});
    if(self)inputs.push({now:26,delta:1,move:[.2,0,.3],yaw:1.1,firstPerson:true,shot:{slot:'light',t0:26}},
      {now:26.1,delta:.1,move:[0,2,0],yaw:1.4,firstPerson:true,entity:{heroY:d.MORPH.GROUND_Y+1,flies:true}},
      {now:26.2,delta:.1,move:[0,0,0],yaw:1.4,firstPerson:false},
      {now:26.3,delta:.1,move:[.1,0,.1],yaw:1.5,firstPerson:false,shot:{slot:'heavy',t0:26.3}});
    for(const input of inputs) {
      const previous=model.position.toArray(),previousYaw=model.rotation.y;
      model.position.add(new model.position.constructor(...input.move));model.position.fromArray(model.position.toArray().map(Math.fround));
      if(!input.firstPerson)model.rotation.y=input.yaw;
      Object.assign(entity,input.entity||{});
      if(self){entity.isSelf=true;model.visible=!input.firstPerson&&!entity.dead;}
      if(input.shot)entity.fireFx=input.shot;if('cast'in input)entity.castFx=input.cast;if(input.heavy)entity.heavyFx=input.heavy;
      if(input.shot)for(const owner of Object.values(forms))unitMotion.fireReferenceWeapon(owner,input.shot);
      if(!input.firstPerson){stepCombatFx(entity,input.now,input.delta);stepLocomotion(entity,input.delta,input.now,previous[0],previous[2],previousYaw);}
      if(self)unitMotion.stepUnitSpinners(model.userData.spin,input.delta);
      model.updateMatrixWorld(true);
      const morph=model.userData.morph;
      const muzzles=[];
      if(cameraProfile) {
        const eye=cameraProfile[entity.flies?'air':'ground'].eye;
        const context={viewMode:'tps',bodyYaw:input.yaw-Math.PI,pos:model.position.clone(),_eyeH:()=>eye,
          camera:{position:model.position.clone().add(new model.position.constructor(5,3,-8))},
          ents:new Map([[1,{isSelf:true,mesh:model}]])};
        const sample=(slot,reach,direction=null,forceFallback=false)=>{
          const marker=model.userData.rig?.muzzles?.[slot],had=marker&&Object.hasOwn(marker,'fxOnly'),saved=marker?.fxOnly;
          if(forceFallback&&marker)marker.fxOnly=true;
          const original=direction?.toArray()??null,origin=BattleClient.prototype._selfMuzzle.call(context,direction,reach,slot);
          muzzles.push({slot,reach,direction:original,forceFallback,eye,bodyYaw:context.bodyYaw,camera:context.camera.position.toArray(),
            result:{origin:origin.toArray(),direction:direction?.toArray()??null}});
          if(forceFallback&&marker){if(had)marker.fxOnly=saved;else delete marker.fxOnly;}
        };
        for(const slot of ['light','heavy','missing']) {
          sample(slot,100);
          for(const reach of [0,5,100,-10])sample(slot,reach,new model.position.constructor(...[.13,.04,-.95].map(Math.fround)));
        }
        sample('light',100,null,true);
      }
      steps.push({...input,previous,previousYaw,position:model.position.toArray(),loco:entity.loco?{...entity.loco}:null,
        active:forms.air&&model.userData.rig===forms.air?'air':'ground',states:stateOf(forms),
        ...('cast'in input?{castInput:input.cast}:{}),...(input.heavy?{heavyInput:input.heavy}:{}),
        fire:entity.fireFx??null,cast:entity.castFx??null,heavy:entity.heavyFx??null,shieldMesh:graph.ids.get(entity.shieldMesh)??null,
        morph:morph?{m:morph.m,k:morph.k,act:morph.act,air:morph.air0}:null,
        uniforms:uniforms(graph),muzzles,nodes:snapshot(graph,before,true)});
    }
    result[self?'authority':'locomotion']={key,phases,entity:'body/'+key,initialState,steps};disposeTree(model);
  }
  {
    const {model,graph,before,forms}=initialize(),entity={id:'events/'+key,pid:1,mesh:model,hero:true,isSelf:false};
    const client={ents:new Map([[entity.id,entity]])},steps=[];
    const inputs=[{serial:1,now:10,type:'weapon_fire',slot:'light'},{serial:1,now:10,type:'weapon_fire',slot:'light',reject:true},
      {serial:2,now:10,type:'weapon_fire',slot:'light'},{serial:3,now:10.1,type:'weapon_fire',slot:'heavy'},
      {serial:4,now:10.2,type:'heavy_charge',on:true},{serial:5,now:10.3,type:'heavy_charge',on:false},
      {serial:6,now:10.4,type:'cast',slot:'atk',fx:'strike',point:[0,0,0]},
      {serial:7,now:10.5,type:'cast_start',slot:'def',fx:'emp',point:[12,0,0]},
      {serial:8,now:10.6,type:'cast',slot:'def',fx:'emp',point:[12.0001,0,0]},
      {serial:9,now:10.7,type:'cast',slot:'atk',fx:'dash',point:[30,0,0],self:true},
      {serial:10,now:10.8,type:'weapon_fire',slot:'unknown'},
      {serial:8,now:11,type:'weapon_fire',slot:'heavy',reject:true},
      {serial:11,now:11.1,type:'body_echo',slot:'light'},
      {serial:12,now:11.2,type:'body_echo',slot:'heavy',self:true},
      {serial:12,now:11.21,type:'body_echo',slot:'heavy',self:true,reject:true,localFire:true},
      {serial:13,now:11.3,type:'body_echo',slot:'light',self:true,localFire:true},
      {serial:14,now:11.4,type:'body_echo',slot:'heavy',self:true,authoritative:true}];
    for(const input of inputs) {
      entity.isSelf=!!input.self;
      if(!input.reject) {
        if(input.type==='weapon_fire')BattleClient.prototype._markFire.call(client,1,input.slot,input.now,null,true);
        else if(input.type==='body_echo') {
          if(!entity.isSelf||input.authoritative)BattleClient.prototype._markFire.call(client,1,input.slot,input.now,null,true);
        }
        else if(input.type==='heavy_charge') {
          const handler=new Function('performance','return function '+BattleClient.prototype.onHeavyCharge.toString())({now:()=>input.now*1000});
          handler.call(client,{pid:1,on:input.on});
        } else if(!entity.isSelf)entity.castFx={t0:input.now,slot:input.slot,dir:d.castDirF(input.fx,Math.hypot(input.point[0],input.point[2])>castRemote)};
      }
      if(input.localFire)BattleClient.prototype._markFire.call(client,1,input.slot,input.now,null,true);
      model.updateMatrixWorld(true);
      steps.push({...input,fire:entity.fireFx??null,heavy:entity.heavyFx??null,cast:entity.castFx??null,
        forms:Object.fromEntries(Object.entries(forms).map(([form,owner])=>[form,{
          indices:Object.fromEntries(Object.entries(owner.weaponSequences||{}).map(([slot,sequence])=>[slot,sequence.index])),
          times:Object.fromEntries(Object.entries(owner.weaponSequences||{}).map(([slot,sequence])=>[slot,sequence.entries.map(entry=>Number.isFinite(entry.firedAt)?entry.firedAt:null)]))
        }])),nodes:snapshot(graph,before,true)});
    }
    result.events={key,steps};disposeTree(model);
  }
  return result;
}
