import {minimapColour} from './minimap_marker_references.mjs';

export function minimapVisionReferences(text,methods,draw,d) {
  const scalar=(source,expression)=>{const match=expression.exec(source);if(!match)throw new Error('Missing original minimap vision seam: '+expression);return Number(match[1]);};
  const colour=/f.fillStyle = '(rgba\([^']+\))';/.exec(draw);
  const relay=text.split('\n').find(line=>line.includes('this._pulseUntil = performance.now()')&&line.includes('FIELD.RELAY.VISION_S'));
  const cast=/const abV = heroAbility\(ev.ch, ev.slot, ev.lvl\)\?\.vision;[\s\S]*?\n      }/.exec(text);
  if(!colour||!relay||!cast)throw new Error('Missing original minimap fog/pulse seams');
  const source=methods.join('\n');
  const rules={cell:scalar(source,/const C = ([\d.]+);/),maximumRadius:scalar(source,/Math.min\(([\d.]+), b.r\)/),
    minimumRadius:scalar(source,/br < ([\d.]+)/),minimumAngleRatio:scalar(source,/br \/ d < ([\d.]+)/),
    farFactor:scalar(source,/const FAR = r \* ([\d.]+)/),maximumShadows:scalar(source,/out.length >= (\d+)/),
    minimumPixels:scalar(draw,/Math.max\(([\d.]+), r \* scXF\)/),softStart:scalar(draw,/rx \* ([\d.]+), 0, 0, rx/),
    colour:minimapColour(colour[1]),exploredRemove:scalar(draw,/f.globalAlpha = ([\d.]+);\n        \/\/ /)};
  const Client=new Function('GAME','UNITS','fogSightMult','FIELD','heroAbility',
    'return class {'+source+'\n_pulse(ev,now){const performance={now:()=>now*1000};if(ev.e==="relay"){'+relay+'}else if(ev.e==="cast"){'+cast[0]+'}}};')
    (d.GAME,d.UNITS,d.fogSightMult,d.FIELD,d.heroAbility);
  const rows=[{kind:'robot',side:'STEEL',hero:true,pid:17,isSelf:true},{kind:'robot',side:'STEEL',hero:true,pid:17},
    {kind:'robot',side:'STEEL',hero:true,pid:18},{kind:'tower',side:'STEEL'},{kind:'soldier',side:'SWARM'},
    {kind:'soldier',side:'STEEL',hp:0},{kind:'soldier',side:'STEEL',dead:true},{kind:'decoy',side:'STEEL',decoy:true,lost:true},
    {kind:'decoy',side:'STEEL',decoy:true},{kind:'kami',side:'STEEL',lost:true},{kind:'hyper',side:'STEEL',lost:true},
    {kind:'unknown',side:'STEEL'},{kind:'civilian',side:''}].map((row,index)=>({pid:0,hero:false,isSelf:false,dead:false,hp:10,decoy:false,lost:false,...row,
      point:[index*7,index*-11]}));
  const vision=[];
  for(const side of ['STEEL','SWARM',''])for(const kind of [null,'robot','drone'])for(const dead of [false,true])
  for(const aiming of [false,true])for(const fog of [0,75,80,100,120]) {
    const client=new Client();Object.assign(client,{side,heroKind:kind,dead,aiming,youId:17,pos:{x:19,z:-23},
      envFx:{getWeatherDynamics:()=>({fog})},ents:new Map(rows.map((row,index)=>[index,{...row,mesh:{position:{x:row.point[0],z:row.point[1]}}}]))});
    vision.push({rows,view:{side,kind:kind??'',dead,aiming,fog,peer:17,point:[19,-23]},sources:client._mmVision()});
  }
  const definitions=[{x:10,z:10,r:3},{x:-64,z:-64,r:1},{x:64,z:64,r:2},{x:0,z:0,r:10},
    {x:25,z:0,r:.5},{x:25,z:10,r:.49999},{x:150,z:0,r:100},{x:200,z:0,r:2,hw2:160,hd2:4,ry:.7},
    ...Array.from({length:150},(_,index)=>({x:60+index%15*11,z:-70+Math.floor(index/15)*15,r:5}))]
    .map((row,index)=>({...row,tag:index}));
  const references=[...definitions.keys(),0];
  const client=new Client(),blockers=references.map(index=>definitions[index]);
  client.terrain={blockers};client._blockGrid=client._buildBlockGrid(blockers);
  const queries=[];
  for(const [x,z,r]of [[0,0,400],[64,64,0],[10,10,1],[0,0,100],[-64,-64,3],[300,300,50],[10000,-10000,10]]) {
    queries.push({point:[x,z],radius:r,tags:client._blockersNear(x,z,r).map(row=>row.tag),shadows:client._mmShadows(x,z,r)});
  }
  const pulses=[];
  const events=[{e:'relay',side:'STEEL'},{e:'relay',side:'SWARM'},
    ...Object.keys(d.CHARACTERS).flatMap(ch=>['def','atk'].flatMap(slot=>[1,2,3,4,1.15,2.5,8.5,16].map(lvl=>({e:'cast',ch,slot,lvl,side:'STEEL',frac:.25,interrupted:true}))))];
  for(const event of events) {
    const instance=new Client();instance.side='STEEL';instance._pulseUntil=50;
    instance._pulse(event,100);
    pulses.push({initial:50,viewer:'STEEL',now:100,event,until:instance._pulseUntil});
  }
  const resets=new Client();resets.side='STEEL';resets._pulseUntil=500;
  const event={e:'relay',side:'STEEL'};resets._pulse(event,100);
  pulses.push({initial:500,viewer:'STEEL',now:100,event,until:resets._pulseUntil});
  return {rules,fixtures:{minimapVision:vision,minimapBlockers:[{definitions,references,queries}],minimapPulses:pulses}};
}
