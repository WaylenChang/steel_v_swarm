import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function localFireReferences(source, d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const text=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
  let clock=10, weather=1;
  const scope={...d,performance:{now:()=>clock*1000},
    weatherFlightAttackRateFactor:()=>weather,weatherGroundAttackRateFactor:()=>weather};
  const compile=body=>new Function(...Object.keys(scope),`return ${body}`)(...Object.values(scope));
  const method=name=>compile(`function ${grabMethod(text,name).trimStart().slice(name.length)}`);
  const fire=grabMethod(text,'_tryFire');
  const end=fire.indexOf("    if (id === 'heavy') this.net?.send({ t: 'heavyFire' });");
  if(end<0) throw new Error('Missing original pre-launch fire presentation boundary');
  const attempt=compile('function(now){'+fire.slice(fire.indexOf('{')+1,end)+'}');
  const tick=method('_tickWeapons'),reload=method('_startReload'),fallback=method('_fallbackFromEmptyHeavy');
  const current=method('_curWeapon'),casting=method('_isCasting');
  const hudSource=grabMethod(text,'_weaponHud');
  const hudStart=hudSource.indexOf('    const slotHud'),hudEnd=hudSource.indexOf('    const snowMul',hudStart);
  if(hudStart<0||hudEnd<hudStart) throw new Error('Missing original local weapon HUD seam');
  const hud=new Function('now',hudSource.slice(hudStart,hudEnd)+"return {light:slotHud('light'),heavy:slotHud('heavy')};");
  const normalize=(def,slot)=>({...def,heavyMp:slot==='heavy'?d.heavyMpCost(def):0,
    burst:{count:d.fireBurstN(def),gap:d.fireBurstGap(def)}});
  const fixtures=[];
  for(const character of Object.keys(d.CHARACTERS)) for(const initialSlot of ['light','heavy']) for(const program of ['sustain','gates']) {
    const wdef=Object.fromEntries(['light','heavy'].map(slot=>[slot,d.heroWeapon(character,slot,1)]));
    const ctx={side:'STEEL',ch:character,dead:false,shopOpen:false,firing:true,freezeLeft:0,empLeft:0,
      castLeft:0,_castingUntil:0,defending:false,sp:100,mp:100000,aiming:initialSlot==='heavy',flight:false,
      lastFireAt:{light:0,heavy:0},_burstN:{},_settleUntil:{},_railAt:0,_steadyAt:0,
      abil:{light:1,heavy:1},
      wdef,wstate:Object.fromEntries(['light','heavy'].map(slot=>[slot,{ammo:3,reloadEnd:0}])),
      flash:{visible:false,scale:{setScalar(){}}},hud:{feed(){}},net:{send(){}},
      _curWeapon:current,_isCasting:casting,_fallbackFromEmptyHeavy:fallback,_startReload:reload,
      _setRailCharge(){},_flying(){return this.flight;},_moveInput(){return this.moving;},
      _setAiming(on){this.aiming=on;this.fallbacks++;},env:{getWeatherDynamics:()=>({snowCdMul:1.7}),getWeatherSurface:()=>({})}};
    ctx.audio={fire:()=>{ctx.played=true;}};
    ctx.hud.feed=value=>ctx.notices.push(value);
    const steps=[];
    const commands=program==='sustain'?Array.from({length:100},(_,i)=>({now:10+i*.12})):[
      {now:10,firing:false},{now:10.1,frozen:true},{now:10.2,casting:true},{now:10.3,emp:true},
      {now:10.4,shop:true},{now:10.5,dead:true},{now:10.6,side:''},{now:10.7,power:0},
      {now:11,moving:true,power:100000},{now:11.1,defending:true},{now:11.2,weather:.3},{now:11.3,weather:0},
      {now:11.5},{now:11.6},{now:12.1},{now:12.3,firing:false},{now:12.4},
      {now:13},{now:14},{now:14.1,reload:true},{now:14.2},{now:16},{now:20}];
    for(const command of commands) {
      clock=command.now;weather=command.weather??1;
      Object.assign(ctx,{side:command.side??'STEEL',dead:!!command.dead,shopOpen:!!command.shop,
        firing:command.firing??true,freezeLeft:command.frozen?1:0,castLeft:command.casting?1:0,
        empLeft:command.emp?1:0,defending:!!command.defending,moving:!!command.moving});
      if('power' in command) ctx.mp=command.power;
      const slot=current.call(ctx).id;
      const frame={side:ctx.side,dead:ctx.dead,shop:ctx.shopOpen,firing:ctx.firing,frozen:!!ctx.freezeLeft,
        casting:!!ctx.castLeft,emp:!!ctx.empLeft,defending:ctx.defending,shield:ctx.sp,aiming:ctx.aiming,
        moving:ctx.moving,weather_rate:weather};
      ctx.played=false;ctx.fallbacks=0;
      ctx.notices=[];
      tick.call(ctx,clock);
      if(!ctx.firing){ctx._railAt=0;ctx._steadyAt=0;ctx._burstN={};}
      if(command.reload) reload.call(ctx,slot);
      attempt.call(ctx,clock);
      const clockBits=Buffer.allocUnsafe(8);
      clockBits.writeDoubleLE(clock);
      steps.push({now:clock,nowBits:clockBits.toString('hex'),slot,frame,reload:!!command.reload,...('power' in command?{power:command.power}:{}),
        ready:ctx.played,fallbacks:ctx.fallbacks,notices:ctx.notices.slice(),hud:hud.call(ctx,clock),result:{power:ctx.mp,lastFire:{...ctx.lastFireAt},
          weapons:Object.fromEntries(Object.entries(ctx.wstate).map(([id,st])=>[id,{ammo:st.ammo,reload_end:st.reloadEnd,...('reloadDur' in st?{reload_duration:st.reloadDur}:{})}])),
          burst:{...ctx._burstN},settle:{...ctx._settleUntil},rail:ctx._railAt||0,steady:ctx._steadyAt||0}});
    }
    fixtures.push({character,initialSlot,program,definitions:Object.fromEntries(Object.entries(wdef).map(([slot,def])=>[slot,normalize(def,slot)])),steps});
  }
  return fixtures;
}
