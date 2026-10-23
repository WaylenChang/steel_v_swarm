// Wire schemas come from server/sim.js; only the original audio consumer decides sound.
export function audioNativeReferences(recorder, cameras) {
  const events = [
    ...['STEEL', 'SWARM'].flatMap(side => ['light', 'heavy'].flatMap(slot => [101, 202].flatMap(pid => [
      {e:'shot', pid, slot, side, from:[30,20], to:[60,50]},
      {e:'plasma', pid, slot, side, x:30, z:20, y:4},
    ]))),
    ...['tower','base','tank','heli','bunker','robot','civilian'].map(kind => ({e:'die',kind,x:30,z:20})),
    ...[0,1,10,60,-3].map(r => ({e:'boom',x:30,z:20,y:4,r})),
    ...['missile_blast','missile_intercept','missile_deflect'].map(nativeType => ({e:'boom',nativeType,x:30,z:20,y:4,r:8})),
    {e:'boom',nativeType:'mine_blast',x:30,z:20,r:8},
    ...['def','atk','ult'].map(slot => ({e:'cast',pid:202,slot,x:30,z:20,r:10})),
    ...[101,202].flatMap(pid => [{e:'crit',pid,x:30,z:20,y:4},{e:'buy',pid}]),
    ...[101,202].map(tpid => ({e:'lock',tpid})),
    {e:'sam',from:[30,20],tpid:101}, {e:'relay',x:30,z:20},
    {e:'airdrop',pid:101,x:30,z:20}, {e:'airfall'},
  ];
  return events.flatMap(event => cameras.map(camera => {
    const native = {type:event.nativeType??event.e};
    for (const key of ['kind','slot','side']) if (key in event) native[key] = event[key];
    if ('tpid' in event) native.target_peer = event.tpid;
    if ('r' in event) native.radius = event.r;
    if ('x' in event) native[event.e === 'cast' ? 'point' : 'position'] = [event.x,130+(event.y||0),-event.z];
    if (event.e === 'shot') { native.start=[30,134,-20]; native.end=[60,132,-50]; }
    if (event.e === 'sam') native.position=[event.from[0],130,-event.from[1]];
    if (['boom','plasma','crit'].includes(event.e)) native.audio_height=event.y;
    recorder.calls=[];
    recorder.onEvent(event,camera,101);
    return {native,actorPeer:event.pid??0,camera,result:recorder.calls};
  }));
}
