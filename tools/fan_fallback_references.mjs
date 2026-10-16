// Execute the original presentation entry points with primitive spies; combat never runs.
export function captureFanFallbackReferences({THREE,d,BattleClient}) {
  const cases=[],lances=[];
  let calls=[],accepted=false;
  const point=value=>value.toArray();
  const scope={THREE,CHARACTERS:d.CHARACTERS,FAN_RANGE_CENTER_F:d.FAN_RANGE_CENTER_F,
    performance:{now:()=>10000},
    fanDischarge(_scene,_effects,from,direction,def,options){
      calls.push({type:'fan',origin:point(from),direction:point(direction),reach:options.range,ch:def.ch,slot:def.slot});return accepted;
    },
    ionBreath(_scene,_effects,from,to,color,options){calls.push({type:'ion',origin:point(from),target:point(to),color,
      radius:options.r,ttl:options.ttl,coil:options.coil,core:options.core,ch:options.def?.ch??null,slot:options.def?.slot??null});},
    beamLine(_scene,_effects,from,to,color,options){calls.push({type:'beam',origin:point(from),target:point(to),color,ttl:options.ttl,width:options.w});},
    starburst(_scene,_effects,x,y,z,radius,color){calls.push({type:'spark',point:[x,y,z],radius,color});},
    shockRing(_scene,_effects,x,y,z,radius,color){calls.push({type:'shock',point:[x,y,z],radius,color});}};
  const local=new Function(...Object.keys(scope),'return function '+BattleClient.prototype._fanBlast.toString().slice('_fanBlast'.length))(...Object.values(scope));
  const source=BattleClient.prototype._onEvent.toString(),marker="} else if (ev.e === 'plasma') {";
  const start=source.indexOf(marker),end=source.indexOf("} else if (ev.e === 'shot') {",start);
  if(start<0||end<=start)throw new Error('Missing original remote plasma presentation branch');
  const remote=new Function(...Object.keys(scope),'ev',source.slice(start+marker.length,end)) ;
  const previousRandom=Math.random;Math.random=()=>.25;
  try {
    for(const character of Object.keys(d.CHARACTERS))for(const slot of ['light','heavy']) {
      const def=d.heroWeapon(character,slot,1);if(d.aoeClass(def)!=='fan')continue;
      for(const mode of ['local','remote'])for(const admission of [false,true])for(const scenario of ['clear','wall','up','zero','defaults','barrel','absent','absent_barrel']) {
        const absent=scenario.startsWith('absent');if(mode==='local'&&absent)continue;
        calls=[];accepted=admission;
        const origin=new THREE.Vector3(12,20,-9),direction=new THREE.Vector3(...(scenario==='up'?[0,1,0]:scenario==='zero'?[0,0,0]:[0,0,1]));
        const side=d.CHARACTERS[character].side,reach=scenario==='defaults'?0:def.range,arc=scenario==='defaults'?0:(def.arc||15);
        const context={scene:null,effects:[],side,youId:-1,terrain:{heightAt:()=>0},_heroEntByPid:()=>absent?null:{ch:character},
          _heroDefOf:(ch,weapon)=>d.heroWeapon(ch,weapon,1),_entMuzzle:()=>origin.clone(),_shotCols:BattleClient.prototype._shotCols,
          _markFire(){},_muzzleBurst(from,heavy,team){calls.push({type:'muzzle',point:point(from),heavy,side:team});},
          _clipBeam(from,to){
            const result=BattleClient.prototype._clipBeam.call({_obstHitT(ax,ay,az,bx,by,bz){
              if(scenario!=='wall'||az===bz)return null;const t=(30-az)/(bz-az);return t>=0&&t<=1?t*Math.hypot(bx-ax,by-ay,bz-az):null;
            }},from,to);
            calls.push({type:'clip',origin:point(from),target:point(to),result:point(result.to)});return result;
          }};
        if(mode==='local')local.call(context,origin,direction,def,reach);
        else remote.call(context,...Object.values(scope),{pid:1,x:12,z:9,y:18,dx:direction.x,dy:direction.y,dz:-direction.z,
          side,slot,r:reach,arc,bar:scenario.endsWith('barrel')});
        cases.push({character,slot,definition:absent?{}:def,mode,admission,scenario,side,reach,arc,origin:point(origin),direction:point(direction),
          hue:absent?null:(d.CHARACTERS[character].visual?.hue??null),calls});
      }
    }
  } finally {Math.random=previousRandom;}
  const lanceScope={THREE,CHARACTERS:d.CHARACTERS,COMBAT_ASSETS:{},lanceR:d.lanceR,
    lanceDischarge(_scene,_effects,from,to,def,color){calls.push({type:'lance',origin:point(from),target:point(to),color});},
    gundamBeam(_scene,_effects,from,to,color,options){calls.push({type:'energy',origin:point(from),target:point(to),color,
      radius:options.r,ttl:options.ttl,rings:options.rings,core:options.core});},
    beamLine(_scene,_effects,from,to,color,options){calls.push({type:'beam',origin:point(from),target:point(to),color,ttl:options.ttl,width:options.w,opacity:options.op??.85});},
    shockRing:scope.shockRing,starburst:scope.starburst};
  const lance=new Function(...Object.keys(lanceScope),'return function '+BattleClient.prototype._lanceVisual.toString().slice('_lanceVisual'.length))(...Object.values(lanceScope));
  for(const character of Object.keys(d.CHARACTERS)) {
    const original=d.heroWeapon(character,'heavy',1);if(d.aoeClass(original)!=='line')continue;
    for(const authored of [false,true])for(const side of ['STEEL','SWARM','SUPER',''])for(const target of [[12,20,-9],[12,100,-9],[40,25,100]]) {
      calls=[];
      const def={...original,ch:authored?character:'missing',lanceRadius:d.lanceR(original)};
      lanceScope.COMBAT_ASSETS[character]=true;
      const origin=new THREE.Vector3(12,20,-9),to=new THREE.Vector3(...target);
      lance.call({_shotCols:BattleClient.prototype._shotCols,scene:null,effects:[]},origin,to,def,side);
      lances.push({definition:def,side,hue:authored?(d.CHARACTERS[character].visual?.hue??null):null,origin:point(origin),target,calls});
    }
  }
  return {fanFallbacks:cases,lanceVisualFallbacks:lances};
}
