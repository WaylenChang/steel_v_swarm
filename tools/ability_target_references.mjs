import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function abilityTargetReferences(source) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const [game,sim]=await Promise.all(['public/js/game.js','server/sim.js'].map(async file=>(await readFile(join(source,file),'utf8')).replace(/\r\n?/g,'\n')));
  const cast=grabMethod(game,'_castAbility');
  const send=cast.split('\n').find(line=>line.includes("this.net.send({ t: 'cast', slot, x:"));
  const heroCast=grabMethod(sim,'heroCast');
  const first=heroCast.indexOf('    if (A.range && x != null)'),last=heroCast.indexOf('    h.mp -= mpc;');
  const distance=/function dist2d\([^)]*\) \{[^\n]+\}/.exec(sim)?.[0];
  if(!send||first<0||last<first||!distance) throw new Error('Missing original client cast wire/authority clamp seam');
  const wire=new Function('x','z',`let result; const slot='def';const capture={send:value=>result=value};${send.replace('this.net.send','capture.send')} return result;`);
  const clamp=new Function('A','h','x','z',`${distance}\n${heroCast.slice(first,last)}\nreturn {x,z};`);
  const points=[];
  for(const origin of [{x:0,z:0},{x:3,z:-8}]) for(const reach of [0,1,40,200]) {
    for(const point of [[0,0],[.05,-.05],[-.05,.05],[1000,-700],[-400,600],[3,8],[43.0001,8]]) {
      const message=wire(...point),result=clamp({range:reach},origin,message.x,message.z);
      points.push({origin,reach,presentation:point,wire:[message.x,message.z],result:[result.x,-result.z]});
    }
  }
  class Vector {
    constructor(x=0,y=0,z=0){Object.assign(this,{x,y,z});}
    distanceTo(v){return Math.hypot(this.x-v.x,this.y-v.y,this.z-v.z);}
  }
  const resolve=new Function('THREE','_ZERO2','_NO_HITS','raySolid',
    `return function ${grabMethod(game,'_resolveAim').trimStart().slice('_resolveAim'.length)}`)
    ({Vector3:Vector},{},[],object=>object.solid!==false);
  const rays=[];
  for(const thirdPerson of [false,true]) for(const cameraDistance of [0,10]) for(const stop of [null,0,7.99,8,12,70]) {
    for(const target of [null,4,8,12,80]) for(const missile of [false,true]) {
      const origin=new Vector(),direction=new Vector(0,0,-1);
      const object={userData:missile?{missileId:17}:{kind:'robot',id:23}};
      const hits=target==null?[]:[{distance:target,point:new Vector(0,0,-target),object}];
      const ctx={camera:{},viewMode:thirdPerson?'tps':'fpv',pos:new Vector(0,0,cameraDistance),
        raycaster:{ray:{origin,direction,at:(t)=>new Vector(0,0,-t)},setFromCamera(){},intersectObjects:()=>hits},
        _rayCandidates:()=>hits,_obstHitT:()=>stop,_terrainHitT:()=>null,_entByMesh:()=>({id:23})};
      const result=resolve.call(ctx,100);
      rays.push({thirdPerson,cameraDistance,stop,target,missile,result:{point:[result.point.x,result.point.y,result.point.z],
        actor:result.ent?.id??0,missile:result.missileId??0}});
    }
  }
  return {points,rays};
}
