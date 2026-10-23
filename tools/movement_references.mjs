import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function movementReferences(d, source, gameSource) {
  const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const text=gameSource.replace(/\r\n/g,'\n');
  const scope={THREE,...d,shockRing(){}};
  const method=name=>{
    const start=text.indexOf(`\n  ${name}(`),end=text.indexOf('\n  }\n',start);
    if(start<0||end<0)throw new Error(`Source movement seam missing: ${name}`);
    return new Function(...Object.keys(scope),`return function ${text.slice(start+1,end+4).trimStart().slice(name.length)}`)(...Object.values(scope));
  };
  const stepLift=method('_stepLift'),chargeJump=method('_chargeJump'),morphLaunch=method('_morphLaunch');
  const unbalanced=method('_unbalanced'),sinkHit=method('_airSinkHit');
  const flightContext=state=>({_flying:()=>state.flying,dead:state.dead,isDrone:state.drone,_altAG:state.altitude,
    _unbalAltThreshold:()=>d.unbalAltThreshold(state.wind),_airSink:state.sink,_airSinkV:state.sink_speed,
    _liftLockUntil:state.lock_until,unbalLeft:state.unbalance_left,defending:state.defending,sp:state.shield,
    env:{getWeatherDynamics:()=>({wind:state.wind})}});
  const movementUnbalance=[];
  for(const flying of [false,true]) for(const dead of [false,true]) for(const drone of [false,true])
    for(const wind of [0,75,87.5,100,150]) for(const altitude of [0,d.unbalAltThreshold(wind)-.00001,d.unbalAltThreshold(wind),d.unbalAltThreshold(wind)+.00001])
      for(const [sink,lock_until,unbalance_left] of [[0,10,0],[1,10,0],[0,10.00001,0],[0,9,1],[1,11,1]]) {
        const state={flying,dead,drone,wind,altitude,sink,sink_speed:2,lock_until,unbalance_left,defending:false,shield:0};
        const ctx={...flightContext(state),lift:25,pos:{y:altitude},_env:{code:0},_liftMax:d.liftMax,
          _liftBaseY:()=>null,_ceilY:()=>500,_unbalanced:unbalanced,hud:{feed(){}}};
        const result=unbalanced.call(ctx,10),target={y:0};
        stepLift.call(ctx,.1,10,target,d.UNITS[drone?'drone':'morph']);
        movementUnbalance.push({state,now:10,result,lift:ctx.lift});
      }
  const movementSinkHits=[];
  for(const flying of [false,true]) for(const drone of [false,true]) for(const wind of [0,80,100])
    for(const altitude of [0,d.unbalAltThreshold(wind)-.00001,d.unbalAltThreshold(wind),100])
      for(const defending of [false,true]) for(const shield of [0,1]) {
        const state={flying,dead:false,drone,wind,altitude,sink:3,sink_speed:7,lock_until:10.2,unbalance_left:0,defending,shield};
        const ctx=flightContext(state),steps=[];
        for(const [damage,now] of [[-1,10],[0,10.1],[1,10.2],[100,10.3],[500,10.4]]) {
          sinkHit.call(ctx,damage,now);
          steps.push({damage,now,result:{sink:ctx._airSink,speed:ctx._airSinkV,lock_until:ctx._liftLockUntil}});
        }
        movementSinkHits.push({state,steps});
      }
  const movementCosts=[];
  for(const charge of [-1,0,.001,.35,.45,.5,.999,1,2]) for(const morph of [false,true]) {
    movementCosts.push({charge,morph,result:morph?d.morphLiftCost(charge):d.cjumpLiftCost(charge)});
  }
  const movementSink=[];
  for(const damage of [-100,0,1,100,500,d.SQUAD.DRONE_AVG_HP]) for(const wind of [0,75,80,100,150]) {
    movementSink.push({damage,wind,result:d.airSinkM(damage,wind)});
  }
  const movementLift=[];
  for(const kind of ['robot','drone','morph']) for(const initial of [null,0,2,100,120]) for(const altitude of [0,26,78,150]) for(const reference of [null,0,50]) for(const wet of [0,1,2,3]) {
    const unit=d.UNITS[kind],ctx={lift:initial,pos:new THREE.Vector3(0,altitude,0),
      _env:{code:wet},_liftMax:d.liftMax,_liftBaseY:()=>reference,_ceilY:()=>500,
      _unbalanced:()=>unbalanced,hud:{feed(){}},env:null};
    const up=unit.vspeed||0,down=unit.vdown??unit.vspeed??0;
    let unbalanced=false;
    const steps=[];
    for(const [index,vertical] of [up,up*2,up*.5,0,-down,-down*.5,0].entries()) {
      unbalanced=index===3;
      const target={y:vertical},dt=index===1?.25:1/60,now=10+index;
      stepLift.call(ctx,dt,now,target,unit);
      steps.push({vertical,delta:dt,now,unbalanced,result:{lift:ctx.lift,vertical:target.y}});
    }
    movementLift.push({kind,initial:initial??-1,altitude,reference,wet,up_speed:up,down_speed:down,
      altitude_factor:d.liftAltF(altitude,reference,500),steps});
  }
  const movementLaunch=[];
  for(const character of Object.keys(d.CHARACTERS)) {
    const kind=d.CHARACTERS[character].kind;
    if(kind==='drone')continue;
    for(const charge of [kind==='morph'?d.MORPH.JUMP_MIN:d.CJUMP.MIN,.75,1]) for(const yaw of [0,.7,-2]) for(const modifier of [1,1.4]) {
      const ctx={charge,pos:new THREE.Vector3(0,20,0),vel:new THREE.Vector3(2,0,3),vy:0,trauma:0,
        scene:null,effects:[],hud:{feed(){}},camera:{getWorldDirection:v=>v.set(-Math.sin(yaw),0,-Math.cos(yaw))},
        _modF:()=>modifier,_jumpMul:()=>1,_mobility:()=>d.heroMobility(kind,d.CHARACTERS[character].mods),
        _reqIframe:()=>{iframes++;}};
      let iframes=0;
      if(kind==='morph')morphLaunch.call(ctx,20);else chargeJump.call(ctx);
      movementLaunch.push({character,kind,charge,yaw,modifier,
        vertical:kind==='morph'?ctx.vel.y:ctx.vy,impulse:[ctx.vel.x,ctx.vel.z],
        position:ctx.pos.toArray(),flying:!!ctx.flight,low_gravity:!!ctx._lowG,iframes});
    }
  }
  return {movementCosts,movementSink,movementLift,movementLaunch,movementUnbalance,movementSinkHits};
}
