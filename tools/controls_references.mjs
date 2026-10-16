import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Capture executed input methods and unmodified fire/recoil blocks from the source client.
export async function controlsReferences(d, gameSource, source) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const text=gameSource.replace(/\r\n/g,'\n');
  let clock=10, preferences={};
  const scope={...d,performance:{now:()=>clock*1000},lookPref:key=>!!preferences[key]};
  const method=name=>new Function(...Object.keys(scope),`return function ${grabMethod(text,name).trimStart().slice(name.length)}`)(...Object.values(scope));
  const applyLook=method('_applyLook'),moveAxis=method('_moveAxis'),moveInput=method('_moveInput'),numpadLook=method('_tickNumpadLook');
  const hold=method('_fireHoldAbility'),rmb=method('_rmbDown'),release=method('_rmbUp');
  const recoiling=method('_recoiling'),moveFactor=method('_recoilMoveF');
  const fireSource=grabMethod(text,'_tryFire');
  const number=(pattern,label,body=text)=>{
    const match=pattern.exec(body);if(!match)throw new Error('Missing original control seam: '+label);
    return Number(match[1]);
  };
  const recoilDecayStart=text.indexOf('    const rk = frictionFPS(RECOIL.DECAY, dt);');
  const recoilDecayEnd=text.indexOf('\n    //',text.indexOf('    const shR =',recoilDecayStart));
  if(recoilDecayStart<0||recoilDecayEnd<0)throw new Error('Missing original recoil decay block');
  const decayBody=text.slice(recoilDecayStart,recoilDecayEnd);
  const rules={mouseSensitivity:number(/movementX \* ([\d.]+)/,'mouse sensitivity'),
    pitchLimit:number(/Math.max\(-([\d.]+), Math.min/,'pitch limit',grabMethod(text,'_applyLook')),
    wheelCooldown:number(/_lastWheelAimAt < ([\d.]+)/,'wheel aim throttle'),
    numpadLookSpeed:number(/const LOOK_SPEED = ([\d.]+)/,'numpad look speed'),
    holdSlots:[d.abilHoldSlot(false),d.abilHoldSlot(true)],
    recoil:{traumaDecay:number(/trauma - dt \* ([\d.]+)/,'trauma decay',decayBody),
      shakeAngle:number(/const shP = .*?\* n \* ([\d.]+)/,'pitch shake',decayBody),
      shakeRoll:number(/const shR = .*?\* n \* ([\d.]+)/,'roll shake',decayBody),
      yawSpread:number(/recoil.y \+= .*?\* ([\d.]+) \*/,'recoil yaw spread',fireSource)}};
  const controlsLook=[];
  for(const frozen of [false,true])for(const invertX of [false,true])for(const invertY of [false,true])for(const system of [false,true]) {
    for(const input of [{yaw:0,pitch:0,change:[.4,.2]},{yaw:9,pitch:1.4,change:[-.8,3]},{yaw:-9,pitch:-1.4,change:[0,-3]}]) {
      preferences={invertX,invertY}; const ctx={yaw:input.yaw,pitch:input.pitch,freezeLeft:frozen?1:0};
      applyLook.call(ctx,...input.change,system);
      controlsLook.push({...input,frozen,invertX,invertY,system,result:[ctx.yaw,ctx.pitch]});
    }
  }
  const controlsMoving=[];
  const controlsNumpad=[];
  for(const keys of [{},{Numpad4:true},{Numpad9:true},{Numpad4:true,Numpad7:true},{Numpad1:true,Numpad8:true},{Numpad1:true,Numpad3:true,Numpad9:true}])for(const paused of [false,true]) {
    const calls=[],ctx={keys,paused,_applyLook:(x,y)=>calls.push([x,y])};
    numpadLook.call(ctx,.03);
    controlsNumpad.push({keys,paused,delta:.03,result:calls});
  }
  for(const keys of [{},{KeyW:true},{KeyD:true,KeyS:true},{Space:true},{KeyC:true},{ControlLeft:true},
    {Space:true,KeyC:true},{ShiftLeft:true}])for(const axis of [null,{f:.01,r:0,mag:.01},{f:.03,r:0,mag:.03}]) {
    const ctx={keys,touch:axis?{axis}:null,_moveAxis:moveAxis},a=moveAxis.call(ctx);
    controlsMoving.push({motion:[a.r,-a.f],held:!!keys.Space,vertical:(keys.Space?1:0)-(keys.KeyC||keys.ControlLeft?1:0),result:moveInput.call(ctx)});
  }
  const controlsStance=[];
  for(const defending of [false,true])for(const dead of [false,true])for(const shop of [false,true])for(const casting of [false,true]) {
    const slots=[],ctx={side:'STEEL',dead,shopOpen:shop,defending,_rmbAbilityFired:false,
      _isCasting:()=>casting,_castAbility:slot=>slots.push(slot),_fireHoldAbility:hold};
    rmb.call(ctx);const fired=!!ctx._rmbAbilityFired; release.call(ctx);
    controlsStance.push({defending,dead,shop,casting,slots,fired,released:!ctx._rmbAbilityFired});
  }
  const segment=(sourceText,startMarker,endMarker)=>{
    const begin=sourceText.indexOf(startMarker),end=sourceText.indexOf(endMarker,begin);
    if(begin<0||end<=begin)throw new Error('Missing original recoil segment: '+startMarker);
    return sourceText.slice(begin,end);
  };
  const recoilBlock=body=>{
    const begin=body.indexOf('    const fly = this._flying();'),back=body.indexOf('    if (prof.back)',begin),end=body.indexOf('\n',back);
    if(begin<0||back<0||end<0)throw new Error('Missing original recoil impulse block');
    return body.slice(begin,end);
  };
  const primary=recoilBlock(fireSource),echoBody=recoilBlock(grabMethod(text,'_burstEchoSelf'));
  const burstBody=segment(fireSource,'    if (prof.burst && !def.fan)', '    if (st.ammo <= 0)');
  const makeBlock=body=>new Function(...Object.keys(scope),`return function(def,id,dir,now,dt){const prof=def?.recoil||{};${body}}`)(...Object.values(scope));
  const kick=makeBlock(burstBody+primary),echoKick=makeBlock(echoBody);
  const decay=makeBlock(decayBody+'\nthis.view=[this.recoil.p+shP,this.recoil.y+shY,shR];');
  const gateBody=segment(fireSource,'    if ((this._settleUntil[id] || 0) > now)', '    this.lastFireAt[id] = now;');
  const gate=makeBlock(gateBody+'\nreturn true;');
  const original=Math.random;
  const withRandom=(values,callback)=>{let at=0;try{Math.random=()=>{if(at>=values.length)throw new Error('Unexpected source recoil RNG draw');return values[at++];};return {value:callback(),draws:at};}finally{Math.random=original;}};
  const chargeChanged=method('_setRailCharge');
  const context=()=>{
    const ctx={recoil:{p:0,y:0},_recoilMoveF0:1,trauma:0,flight:false,view:null,
    vel:{x:0,y:0,z:0,addScaledVector(v,s){this.x+=v.x*s;this.y+=v.y*s;this.z+=v.z*s;}},
    flash:{visible:false,scale:{setScalar(){}}},_burstN:{},_settleUntil:{},_railAt:0,_steadyAt:0,
    _recoiling:recoiling,_flying(){return this.flight;},_moveInput(){return !!this.moving;},_setRailCharge:chargeChanged,hud:{feed(){}},chargeEvents:[]};
    ctx.net={send:event=>ctx.chargeEvents.push(event.on)};
    return ctx;
  };
  const state=ctx=>({pitch:ctx.recoil.p,yaw:ctx.recoil.y,trauma:ctx.trauma,move_factor:ctx._recoilMoveF0,
    groundFactor:moveFactor.call(ctx,false),airFactor:moveFactor.call(ctx,true),velocity:[ctx.vel.x,ctx.vel.y,ctx.vel.z],
    burst_count:{...ctx._burstN},settle_until:{...ctx._settleUntil},rail_at:ctx._railAt,steady_at:ctx._steadyAt,
    view:ctx.view?ctx.view.slice():null});
  const recoilSequences=[];
  const direction={x:.3,y:.4,z:-Math.sqrt(.75)};
  const programs=[{name:'mixed',commands:[{kind:'fire',slot:'heavy',now:10},{kind:'fire',slot:'light',now:10.01},
    {kind:'echo',slot:'light',now:10.02},{kind:'decay',now:10.04,delta:.04},
    {kind:'fire',slot:'light',now:10.1},{kind:'release',now:10.11},
    {kind:'decay',now:11,delta:.9},{kind:'fire',slot:'light',now:11.1},{kind:'decay',now:13,delta:1.9}]},
    {name:'pulse',commands:[{kind:'fire',slot:'heavy',now:10},{kind:'decay',now:10.04,delta:.04}]}];
  for(const character of Object.keys(d.CHARACTERS))for(const flight of [false,true])for(const program of programs) {
    const ctx=context();ctx.flight=flight;const steps=[];
    for(const command of program.commands) {
      const randoms=command.kind==='decay'?[.1,.8,.4]:[.37];
      let draws=0;
      if(command.kind==='fire'||command.kind==='echo') {
        const definition=d.heroWeapon(character,command.slot,1);
        draws=withRandom(randoms,()=> (command.kind==='fire'?kick:echoKick).call(ctx,definition,command.slot,direction,command.now)).draws;
      } else if(command.kind==='decay') draws=withRandom(randoms,()=>decay.call(ctx,null,null,null,command.now,command.delta)).draws;
      else {ctx._railAt=0;ctx._steadyAt=0;ctx._burstN={};}
      steps.push({...command,randoms,draws,result:state(ctx)});
    }
    recoilSequences.push({name:program.name,character,flight,direction:[direction.x,direction.y,direction.z],steps});
  }
  const recoilGates=[];
  for(const type of ['gun','rail'])for(const steady of [0,.5])for(const charge of [0,.7]) {
    const ctx=context(),steps=[];
    const definition={...d.heroWeapon('t01','heavy',1),type,charge,recoil:{...d.RECOIL.heavy.high,steady}};
    for(const command of [{now:10,moving:true},{now:10.2,moving:false},{now:10.6,moving:false},
      {now:10.9,moving:false},{now:11,moving:true},{now:11.1,moving:false},{now:12,moving:false},{now:12.2,release:true},{now:12.3,moving:false}]) {
      ctx.moving=!!command.moving;
      ctx.chargeEvents.length=0;
      if(command.release){ctx._railAt=0;ctx._steadyAt=0;ctx._burstN={};ctx._setRailCharge(false);}
      const ready=command.release?false:gate.call(ctx,definition,'heavy',null,command.now)===true;
      steps.push({...command,ready,chargeEvents:ctx.chargeEvents.slice(),charging:!!ctx._railCharging,result:state(ctx)});
    }
    recoilGates.push({definition,steps});
  }
  return {rules,fixtures:{controlsLook,controlsMoving,controlsNumpad,controlsStance,recoilSequences,recoilGates}};
}
