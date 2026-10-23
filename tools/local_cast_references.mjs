import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function localCastReferences(source, d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const text=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
  let clock=10;
  class Vector {
    constructor(){this.x=0;this.y=0;this.z=-1;}
    normalize(){return this;}
  }
  const scope={...d,THREE:{Vector3:Vector},performance:{now:()=>clock*1000}};
  const method=name=>new Function(...Object.keys(scope),`return function ${grabMethod(text,name).trimStart().slice(name.length)}`)(...Object.values(scope));
  const request=method('_castAbility'),casting=method('_isCasting'),hud=method('_weaponHud');
  const number=pattern=>{
    const match=pattern.exec(text);
    if(!match) throw new Error('Missing original local cast timing: '+pattern);
    return Number(match[1]);
  };
  const timing={attackDefaultSeconds:d.ATK_CAST_S,
    startDefaultSeconds:number(/this\._castingUntil = performance.now\(\) \/ 1000 \+ \(ev.dur \|\| ([\d.]+)\)/),
    expansionDefaultSeconds:number(/this.shieldExpandUntil = now \+ \(A.dur \|\| ([\d.]+)\)/),
    cooldownDefaultSeconds:number(/this.cds\[idx\] = \(A.cd \|\| ([\d.]+)\)/),
    hudMinimumSeconds:number(/cdMax: Math.max\(([\d.]+), \(A.cd \|\|/),
    aimRangeMultiplier:number(/_resolveAim\(Math.max\(A.range \* ([\d.]+),/),
    aimMinimumRange:number(/_resolveAim\(Math.max\(A.range \* [\d.]+, ([\d.]+)\)/),
    rearStopFactor:number(/if \(dStop < camDist \* ([\d.]+)\)/)};
  const fixtures=[];
  for(const character of Object.keys(d.CHARACTERS)) for(const slot of ['def','atk']) for(const level of [1,4]) {
    const definition=d.heroAbility(character,slot,level);
    if(!definition) throw new Error('Missing original local ability definition');
    const cost=Math.round(definition.mp);
    for(const variation of [{},{side:''},{dead:true},{shop:true},{frozen:true},{emp:true},
      {castLeft:.1},{until:10.1},{cooldown:3},{cooldown:3,charges:[1,2,3]},
      {cooldown:0,charges:[0,2,3]},{cooldown:3,charges:[0,2,3]},
      {power:cost-.01},{power:cost},{locked:false},{snow:1.7},{snow:0}]) {
      const frame={side:'STEEL',dead:false,shop:false,frozen:false,emp:false,power:100000,locked:true,snow:1,...variation};
      const cooldowns=[variation.cooldown??0,variation.cooldown??0];
      const charges=variation.charges?[variation.charges.slice(),variation.charges.slice()]:null;
      const messages=[];
      const notices=[];
      const ctx={side:frame.side,dead:frame.dead,shopOpen:frame.shop,ch:character,freezeLeft:frame.frozen?1:0,
        castLeft:variation.castLeft??0,_castingUntil:variation.until??0,abil:{def:level,atk:level},
        cds:cooldowns.slice(),chg:charges?structuredClone(charges):null,mp:frame.power,empLeft:frame.emp?1:0,
        _lockId:frame.locked?1:null,pos:{x:3,z:4},shieldExpandUntil:0,defJumpUntil:0,
        net:{send:value=>messages.push(value)},hud:{feed:value=>notices.push(value)},_isCasting:casting,
        _resolveAim:()=>({point:{x:40,z:-20}}),_updateShieldVisibility(){},
        env:{getWeatherDynamics:()=>({snowCdMul:frame.snow})},
        camera:{getWorldDirection:v=>v},_flying:()=>false,vel:{addScaledVector(){}},trauma:0};
      clock=10;
      request.call(ctx,slot);
      ctx.wdef=Object.fromEntries(['light','heavy'].map(id=>[id,d.heroWeapon(character,id,1)]));
      ctx.wstate=Object.fromEntries(Object.entries(ctx.wdef).map(([id,def])=>[id,{ammo:def.mag,reloadEnd:0}]));
      ctx.abil.light=1;ctx.abil.heavy=1;ctx._atBase=()=>false;ctx._liftMax=()=>100;
      ctx.isDrone=false;ctx.isMorph=false;
      const displayed=hud.call(ctx);
      fixtures.push({character,slot,level,definition,frame,initial:{cooldowns,charges,
        castLeft:variation.castLeft??0,until:variation.until??0},ready:messages.length>0,notices,
        result:{cooldowns:ctx.cds,charges:ctx.chg,castLeft:ctx.castLeft,until:ctx._castingUntil,
          shieldExpandUntil:ctx.shieldExpandUntil,defJumpUntil:ctx.defJumpUntil,power:ctx.mp},
        hud:displayed?{def:displayed.def,atk:displayed.atk}:null});
    }
  }
  return {timing,fixtures};
}
