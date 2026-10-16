// Execute the original remote _updateEnts statements and lane profile builder offline.
export function captureBodyViewReferences({THREE,d,BattleClient,lod}) {
  const source=BattleClient.prototype._updateEnts.toString();
  const start=source.indexOf('      const cur = ent.mesh.position;');
  const finish=source.indexOf('      cur.set(nx, ny, nz);',start);
  const staticStart=source.indexOf('        const y = ent.padY ??');
  const staticFinish=source.indexOf('        if (sDue) {',staticStart);
  if(start<0||finish<start||staticStart<0||staticFinish<staticStart)throw new Error('Missing original remote/static body frame seams');
  const scope={lerpFPS:d.lerpFPS,lodDue:lod.lodDue,lodStrideByD2:lod.lodStrideByD2,UNITS:d.UNITS};
  const update=new Function(...Object.keys(scope),'ent','dt','now','camP','lp','lodFrame',
    'const oldY=ent.mesh.position.y;'+source.slice(start,finish)+'cur.set(nx, ny, nz);return {due,previous:[px,oldY,pz],previousYaw:pyaw,snapped};');
  const updateStatic=new Function(...Object.keys(scope),'ent','dt','now','camP','lp','lodFrame',
    'const previous=ent.mesh.position.toArray(),previousYaw=ent.mesh.rotation.y;'+source.slice(staticStart,staticFinish)
      +'return {due:sDue,previous,previousYaw,snapped:false};');
  const frames=[];
  for(const kind of ['soldier','heli','drone_wingman','robot','kami','hyper','civilian','tower'])for(const far of [false,true]) {
    const mesh=new THREE.Group();mesh.position.set(0,10,0);if(kind==='hyper')mesh.rotation.order='YXZ';
    const entity={id:'view/'+kind,kind,side:kind==='civilian'?'':'STEEL',mesh,hero:kind==='robot',flies:['heli','drone_wingman','kami','hyper'].includes(kind),
      kami:kind==='kami',hyper:kind==='hyper',decoy:false,isStatic:kind==='tower',heroY:0,_snapPos:true,tgt:new THREE.Vector3()},steps=[];
    const inputs=[{delta:.016,now:10,frame:0,target:[0,0,0],yaw:1.2,surface:10,ground:10},
      {delta:.016,now:10.016,frame:1,target:[.2,0,0],yaw:3.12,surface:11,ground:10,lane:8},
      {delta:.1,now:10.116,frame:2,target:[10,0,-10],yaw:-3.12,surface:12,ground:10,heroY:5,deck:15},
      {delta:.003999,now:10.12,frame:3,target:[10,0,-10],yaw:-3,surface:13,ground:11,heroY:6,deck:16},
      {delta:.03,now:10.15,frame:4,target:[10,0,-10],yaw:0,surface:14,ground:8,heroY:8,tunnel:{floor:0,ceil:18,roof:19,open:false}},
      {delta:.03,now:10.18,frame:5,target:[10,0,-10],yaw:0,surface:3,ground:8,heroY:0,tunnel:{floor:0,ceil:18,roof:19,open:true}},
      {delta:.5,now:10.68,frame:6,target:[10,0,-10],yaw:0,surface:-5,ground:-5,water:0,deck:3},
      {delta:.5,now:11.18,frame:7,target:[10,0,-10],yaw:0,surface:-5,ground:-5,water:0},
      {delta:2,now:13.18,frame:8,target:[10,0,-10],yaw:0,surface:4,ground:0,nearest:[-10,2,10]},
      {delta:.1,now:13.28,frame:9,target:[10,0,-10],yaw:2,surface:6,ground:1,aim:{x:10,y:30,z:40,until:13.38}},
      {delta:.1,now:13.38,frame:10,target:[10,0,-10],yaw:2,surface:6,ground:1,nearest:[30,40,50],nearestSelf:true},
      {delta:.1,now:13.48,frame:11,target:[-30,0,40],yaw:-2,surface:6,ground:1,snap:true,pad:12},
      {delta:.1,now:13.58,frame:4294967295,target:[-30,0,40],yaw:-2,surface:6,ground:1,nearest:[-20,8,30]},
      {delta:0,now:13.6,frame:0,target:[40,0,-30],yaw:1,surface:8,ground:2,nearest:[-20,8,30]},
      {delta:0,now:13.7,frame:1,target:[40,0,-30],yaw:1,surface:9,ground:3,snap:true},
      {delta:0,now:13.8,frame:2,target:[40,0,-30],yaw:1,surface:10,ground:4}];
    for(const input of inputs) {
      const queries=[],camera=new THREE.Vector3(far?1500:0,0,0);
      entity.tgt.fromArray(input.target.map(Math.fround));entity.ry=input.yaw;
      entity.heroY=input.heroY??entity.heroY;if(input.aim)entity._aimAt={...input.aim};if(input.snap)entity._snapPos=true;
      entity.padY=input.pad??null;
      const terrain={heightAt:(x,z)=>{if(entity.isStatic)queries.push(['ground',x,z]);return input.ground;},waterY:input.water??null,
        deckMargin:0,deckY:()=>input.deck??null,tunnelAt:()=>input.tunnel??null,
        surfaceAt:(x,z,seed)=>{queries.push(['surface',x,z,seed]);return input.surface;}};
      const client={terrain,pos:new THREE.Vector3(60,7,-20),_surf:BattleClient.prototype._surf,
        _flySurf(x,z){queries.push(['flight',x,z]);return BattleClient.prototype._flySurf.call(this,x,z);},
        _laneSurfAt(x,z){queries.push(['lane',x,z]);return input.lane??null;},
        _nearestEnemy(ent,now){queries.push(['nearest',now,...ent.mesh.position.toArray()]);return input.nearest?
          {mesh:{position:new THREE.Vector3(...input.nearest)},isSelf:!!input.nearestSelf}:null;}};
      const deck=terrain.deckY;terrain.deckY=(x,z,...rest)=>{if(!entity.flies)queries.push(['deck',x,z]);return deck(x,z,...rest);};
      const result=(entity.isStatic?updateStatic:update).call(client,...Object.values(scope),entity,input.delta,input.now,camera,false,input.frame);
      if(result.due)entity._lodAcc=0;
      steps.push({...input,reportedYaw:input.yaw,camera:camera.toArray(),target:entity.tgt.toArray(),queries,result,
        position:mesh.position.toArray(),yaw:mesh.rotation.y,pitch:mesh.rotation.x,cached:entity._lodGy??null});
    }
    frames.push({kind,side:entity.side,hero:entity.hero,flies:entity.flies,static:entity.isStatic,initial:[0,10,0],id:entity.id,steps});
  }
  const laneProfiles=[];
  for(const paths of [[],[[[0,0]]],[[[0,0],[0,0],[10,0]]],[[[-40,-40],[40,-40]],[[0,-40],[0,40]]],
    [[[0,0],[3,0]],[[0,0],[8,0]],[[0,20],[8,20]]],[[[0,0],[8,3],[8,3],[20,20]]]]) {
    const queries=[],client={lanePts:paths.map(path=>path.map(([x,z])=>new THREE.Vector3(x,0,z))),
      terrain:{heightAt:(x,z)=>x*.1+z*.2},_surf(x,z,seed){queries.push([x,z,seed]);return Math.max(x*.1+z*.2,seed>10?12:0);}};
    BattleClient.prototype._buildLaneSurf.call(client);
    const samples=[];for(const x of [-40,-20,-.001,0,4,8,20,40,60])for(const z of [-40,-20,0,10,20,40,60])
      samples.push({x,z,result:client._laneSurfAt(x,z)});
    laneProfiles.push({paths,queries,lanes:client._laneSurf,samples});
  }
  return {frames,laneProfiles};
}
