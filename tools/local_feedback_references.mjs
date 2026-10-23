import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function localFeedbackReferences(source) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
  const fire=grabMethod(game,'_tryFire'),cast=grabMethod(game,'_castAbility'),reload=grabMethod(game,'_startReload'),defense=grabMethod(game,'_toggleDefense');
  const section=(body,first,last)=>{
    const begin=body.indexOf(first),end=body.indexOf(last,begin+first.length);
    if(begin<0||end<0) throw new Error('Missing original local feedback section: '+first);
    return body.slice(begin,end);
  };
  const replacements={'def.name':'name','A.name':'name','mpc':'cost','cdLeft.toFixed(0)':'seconds'};
  const decode=quoted=>{
    const value=quoted.replace(/\$\{([^}]+)\}/g,(_,expression)=>{
      const key=replacements[expression.trim()];
      if(!key) throw new Error('Unsupported original feedback interpolation: '+expression);
      return '{'+key+'}';
    });
    return new Function('return '+value)();
  };
  const feed=body=>{
    const at=body.indexOf('this.hud.feed?.(');
    if(at<0) throw new Error('Missing original HUD feed call');
    const expression=body.slice(at+'this.hud.feed?.('.length).trimStart();
    const quoted=/^(?:'(?:\\.|[^'])*'|`(?:\\.|[^`])*`)/.exec(expression)?.[0];
    if(!quoted) throw new Error('Unsupported original HUD feed expression');
    return decode(quoted);
  };
  const interval=(body,key)=>{
    const value=new RegExp('now - \\(this\\._'+key+'WarnAt \\|\\| 0\\) > ([\\d.]+)').exec(body)?.[1];
    if(value===undefined) throw new Error('Missing original local notice interval: '+key);
    return Number(value);
  };
  const entry=(text,clock=null,cooldown=null)=>({text,clock,cooldown});
  const rules={
    fire_casting:entry(feed(section(fire,'if (this._isCasting(now))','if (this.empLeft > 0)')),'cast',interval(fire,'cast')),
    fire_emp:entry(feed(section(fire,'if (this.empLeft > 0)',"if (this._railAt && def.type !== 'rail')")),'emp',interval(fire,'emp')),
    fire_power:entry(feed(section(fire,'if (mpc > 0 && this.mp < mpc)','const prof')),'mp',interval(fire,'mp')),
    steady_move:entry(feed(section(fire,'if (prof.steady > 0)',"if (def.type !== 'rail')")),'steady',interval(fire,'steady')),
    steady_start:entry(feed(section(fire,"if (def.type !== 'rail')",'const sp'))),
    rail_start:entry(feed(section(fire,"if (def.type === 'rail' && def.charge)",'const p'))),
    cast_busy:entry(feed(section(cast,'if (this._isCasting(now))','const idx')),'cast',interval(cast,'cast')),
    cast_cooldown:entry(feed(section(cast,'if (readyCharges <= 0 && cdLeft > 0)','const mpc'))),
    cast_power:entry(feed(section(cast,'if (this.mp < mpc)','if (this.empLeft > 0)'))),
    cast_emp:entry(feed(section(cast,'if (this.empLeft > 0)','if (A.range > 0'))),
    cast_lock:entry(feed(section(cast,'if (A.range > 0','let x = this.pos.x'))),
    defense_empty:entry(feed(section(defense,'if (!this._canEnterDefense())','this.defending = true;'))),
    defense_on:entry(feed(defense.slice(defense.indexOf('this.defending = true;')))),
    defense_off:entry(feed(defense.slice(defense.indexOf('this.defending = false;')))),
  };
  const reloadFeed=reload.slice(reload.indexOf('this.hud.feed?.('));
  const reloadTexts=[...reloadFeed.matchAll(/`(?:\\.|[^`])*`/g)].map(match=>decode(match[0]));
  if(reloadTexts.length!==2) throw new Error('Missing original light/heavy reload notices');
  rules.reload_heavy=entry(reloadTexts[0]);rules.reload_light=entry(reloadTexts[1]);
  const prefix=(method,last)=>new Function('now',method.slice(method.indexOf('{')+1,method.indexOf(last)));
  const fireBusy=prefix(fire,'    if (this.empLeft > 0)');
  const castBusy=new Function('performance',cast.slice(cast.indexOf('{')+1,cast.indexOf('    const idx')));
  const ctx={side:'STEEL',dead:false,shopOpen:false,ch:'t01',firing:true,freezeLeft:0,_isCasting:()=>true,
    _curWeapon:()=>({id:'light',def:{},st:{}})};
  const mixed=[];
  for(const [id,now] of [['fire_casting',.5],['cast_busy',1.2],['fire_casting',1.20001],
    ['cast_busy',1.3],['cast_busy',2.40002],['fire_casting',2.5],['fire_casting',3.7]]) {
    const notices=[];ctx.hud={feed:text=>notices.push(text)};
    if(id==='cast_busy') castBusy.call(ctx,{now:()=>now*1000});
    else fireBusy.call(ctx,now);
    mixed.push({id,now,notices,last:ctx._castWarnAt||0});
  }
  return {rules,mixed};
}
