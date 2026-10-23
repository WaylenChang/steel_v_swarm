import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function localDefenseReferences(source) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const [game,vfx,sim]=await Promise.all(['public/js/game.js','public/js/vfx.js','server/sim.js'].map(async file=>(await readFile(join(source,file),'utf8')).replace(/\r\n?/g,'\n')));
  const expand=Number(/export const SHIELD_PRESENTATION_EXPAND = ([\d.]+)/.exec(vfx)?.[1]);
  if(!Number.isFinite(expand)) throw new Error('Missing original shield expansion scale');
  const clock=10;
  const method=name=>new Function('performance','SHIELD_PRESENTATION_EXPAND',
    `return function ${grabMethod(game,name).trimStart().slice(name.length)}`)({now:()=>clock*1000},expand);
  const toggle=method('_toggleDefense'),enter=method('_canEnterDefense'),visibility=method('_updateShieldVisibility');
  const depletion=game.split('\n').find(line=>line.includes('if (this.defending && (this.sp || 0) <= 0) this._toggleDefense(false);'));
  if(!depletion) throw new Error('Missing original shield-depletion transition');
  const drain=new Function(depletion);
  const programs=[[
    {kind:'request'},{kind:'request',on:true},{kind:'snapshot',frozen:true,shield:50},
    {kind:'snapshot',frozen:false,shield:0},{kind:'frame'},{kind:'request',shield:0},
    {kind:'request',shield:50},{kind:'request',on:false,frozen:true},{kind:'request',on:false,frozen:false},
    {kind:'request',on:false},{kind:'request',dead:true},{kind:'request',dead:false,shop:true},
    {kind:'request',shop:false,side:''},{kind:'request',side:'STEEL'},
    {kind:'frame',dead:true},{kind:'frame',dead:false},
  ]];
  const fixtures=[];
  for(const initial of [false,true]) for(const program of programs) {
    const ctx={defending:initial,freezeLeft:0,side:'STEEL',dead:false,shopOpen:false,sp:50,viewMode:'fpv',shieldExpandUntil:0,
      ents:new Map(),_canEnterDefense:enter,_toggleDefense:toggle,_updateShieldVisibility:visibility};
    const steps=[];
    for(const operation of program) {
      const frame={side:operation.side??ctx.side,dead:operation.dead??ctx.dead,shop:operation.shop??ctx.shopOpen,
        shield:operation.shield??ctx.sp,frozen:operation.frozen??(ctx.freezeLeft>0)};
      const notices=[],sent=[];
      ctx.hud={feed:text=>notices.push(text)};ctx.net={send:message=>sent.push(message.on)};
      Object.assign(ctx,{side:frame.side,dead:frame.dead,shopOpen:frame.shop,sp:frame.shield});
      if(operation.kind==='snapshot') {
        drain.call(ctx);ctx.freezeLeft=frame.frozen?1:0;
      } else {
        ctx.freezeLeft=frame.frozen?1:0;
        if(operation.kind==='frame') {if(!ctx.dead) drain.call(ctx);}
        else if('on' in operation) toggle.call(ctx,operation.on);
        else toggle.call(ctx);
      }
      steps.push({...operation,frame,notices,sent,result:{defending:ctx.defending,frozen:ctx.freezeLeft>0}});
    }
    fixtures.push({initial,steps});
  }
  const freezeLine=sim.split('\n').find(line=>line.includes('o.fz = Math.round((e.freezeUntil - this.t) * 10) / 10'));
  if(!freezeLine) throw new Error('Missing original published freeze precision');
  const remaining=new Function('e','const o={};'+freezeLine+';return o.fz||0;');
  const deadlines=[0,9.999,10,10.01,10.049999,10.05,10.050001,11].map(deadline=>
    ({deadline,now:10,result:remaining.call({t:10},{freezeUntil:deadline})}));
  return {programs:fixtures,deadlines};
}
