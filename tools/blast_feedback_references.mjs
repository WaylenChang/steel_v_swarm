import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { readFile } from 'node:fs/promises';

// Original client method is the oracle; no native impulse calculation supplies expectations.
export async function blastFeedbackReferences(d,gameSource,source,BattleSim) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const method=grabMethod(gameSource.replace(/\r\n/g,'\n'),'_applyBlast');
  const apply=new Function('THREE','SHAKE','return function '+method.trimStart())(THREE,d.SHAKE);
  const cases=[];
  for(const radius of [-1,0,.001,3,12,40])for(const flying of [false,true])for(const height of [0,16])
    for(const eyeOffset of [0,60])for(const trauma of [0,.8])for(const gate of ['live','dead','noSide']) {
      const reach=radius*d.SHAKE.BLAST_F;
      for(const offset of [0,.19999,.20001,Math.max(0,reach)*.5,Math.max(0,reach),Math.max(0,reach)+.001]) {
        const position=[12,20,-9].map(Math.fround),eye=[12+eyeOffset,24,-9].map(Math.fround);
        const point=[12+offset,20+(height||2)*.5,-9].map(Math.fround),yaw=.7;
        const initial={velocity:[1.25,-2.5,3.75],lift:1.5};
        const client={side:gate==='noSide'?'':'STEEL',dead:gate==='dead',camera:{position:new THREE.Vector3(...eye)},
          pos:new THREE.Vector3(...position),vel:new THREE.Vector3(...initial.velocity),selfH:height,yaw,vy:initial.lift,
          trauma,_flying:()=>flying};
        apply.call(client,...point,radius);
        const delta=client.vel.clone().sub(new THREE.Vector3(...initial.velocity));
        cases.push({point,radius,position,eye,height,yaw,flying,trauma,hasSide:!!client.side,dead:client.dead,
          result:{trauma:client.trauma,velocity:delta.toArray(),lift:client.vy-initial.lift}});
      }
    }
  const text=gameSource.replace(/\r\n/g,'\n');
  const eventSource=grabMethod(text,'_onEvent');
  const marker="    } else if (ev.e === 'boom') {",start=eventSource.indexOf(marker),end=eventSource.indexOf("    } else if (ev.e === 'decoyBomb')",start);
  if(start<0||end<=start)throw new Error('Missing original boom presentation seam');
  let calls=[];
  const record=(type,x,y,z,settings)=>calls.push({type,point:[x,y,z],...settings});
  const boom=new Function('shockRing','ev',eventSource.slice(start+marker.length,end));
  const reports=[];
  const captureReport=event=>{
    calls=[];
    boom.call({terrain:{heightAt:()=>23},_explosion:(x,y,z,radius,color)=>record('explosion',x,y,z,{radius,color}),
      _emberBurst:(x,y,z,count,spread)=>record('embers',x,y,z,{count,spread}),
      _applyBlast:(x,y,z,radius)=>record('blast',x,y,z,{radius})},
      (_scene,_effects,x,y,z,radius,color)=>record('shock',x,y,z,{radius,color}),event);
    return calls;
  };
  for(const y of [null,0,2,11.999,12,30])for(const radius of [0,3,16])for(const style of ['normal','kami','sam']) {
    const event={e:'boom',x:12,z:9,r:radius,...(y==null?{}:{y}),kami:style==='kami',sam:style==='sam'};
    reports.push({event,ground:23,calls:captureReport(event)});
  }
  const protocol=[];
  const missiles={events:[],ents:new Map(),_blast:()=>{}};
  BattleSim.prototype._samBlast.call(missiles,{byId:9,side:'STEEL',r:8,pen:0,dmg:100},12,9,1);
  protocol.push({native:'missile_blast',event:missiles.events.pop()});
  const serverText=(await readFile(join(source,'server/sim.js'),'utf8')).replace(/\r\n/g,'\n');
  const intercepted=/this\.events\.push\(\{ e: 'boom', missileId:m\.id,[^\n]+\}\);/.exec(serverText)?.[0];
  const reflected=/this\.events\.push\(\{ e: 'boom', x: m\.x \+ fx \* 15,[^\n]+\}\);/.exec(serverText)?.[0];
  if(!intercepted||!reflected)throw new Error('Missing original missile interception/reflection boom report seams');
  const missile={id:7,x:12,z:9,y:1,r:8};
  new Function('h','m',intercepted).call(missiles,{side:'STEEL'},missile);
  protocol.push({native:'missile_intercept',event:missiles.events.pop()});
  new Function('m','t','fx','fz',reflected).call(missiles,missile,{side:'STEEL'},1,0);
  protocol.push({native:'missile_deflect',event:missiles.events.pop()});
  for(const item of protocol){item.ground=23;item.calls=captureReport(item.event);}
  const bullets=grabMethod(text,'_updateBullets');
  const localStart=bullets.indexOf('        const btn = this.terrain.tunnelAt?.(p.x, p.z);');
  const localEnd=bullets.indexOf('this._applyBlast(p.x, by, p.z, b.r || 12);',localStart);
  if(localStart<0||localEnd<=localStart)throw new Error('Missing original local projectile blast point seam');
  const local=new Function('p','b',bullets.slice(localStart,localEnd+'this._applyBlast(p.x, by, p.z, b.r || 12);'.length));
  const localPoints=[];
  for(const tunnel of [null,{floor:0,ceil:18,open:false},{floor:0,ceil:18,open:true}])for(const y of [-3,0,17.999,18,25])for(const radius of [null,0,3,16]) {
    calls=[];const position=[12,y,-9];
    local.call({terrain:{heightAt:()=>23,tunnelAt:()=>tunnel},_explosion:(x,y,z,radius,color)=>record('explosion',x,y,z,{radius,color}),
      _applyBlast:(x,y,z,radius)=>record('blast',x,y,z,{radius})},new THREE.Vector3(...position),{r:radius});
    localPoints.push({position,tunnel,ground:23,radius,calls});
  }
  const sequences=[];
  for(const flying of [false,true]) {
    const client={side:'STEEL',dead:false,camera:{position:new THREE.Vector3(0,8,0)},pos:new THREE.Vector3(),vel:new THREE.Vector3(),
      selfH:16,yaw:.7,vy:0,trauma:0,_flying:()=>flying},steps=[];
    for(let index=0;index<2;index++) {
      apply.call(client,1,8,0,12);
      steps.push({velocity:client.vel.toArray(),lift:client.vy,trauma:client.trauma});
    }
    sequences.push({flying,radius:12,steps});
  }
  return {blastFeedback:cases,blastReports:reports,blastProtocol:protocol,localBlastPoints:localPoints,blastFeedbackSequences:sequences};
}
