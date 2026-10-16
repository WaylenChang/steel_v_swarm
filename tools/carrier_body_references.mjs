// Original _updateEnts heading/pitch statements; no trajectory or physics approximation.
export function captureCarrierBodyMotion({THREE,BattleClient,d}) {
  const source=BattleClient.prototype._updateEnts.toString();
  const start=source.indexOf('      let wantYaw = null;'),end=source.indexOf('      cur.set(nx, ny, nz);',start);
  if(start<0||end<start)throw new Error('Missing original carrier pose seam');
  const pose=new Function('ent','cur','nx','ny','nz','px','pz','pyaw','snapped','dt','now','lerpFPS',source.slice(start,end));
  const result=[];
  for(const kind of ['decoy','kami','hyper']) {
    const mesh=new THREE.Group();if(kind==='hyper')mesh.rotation.order='YXZ';
    const initial=[12,20,-9];mesh.position.fromArray(initial);
    const entity={mesh,decoy:kind==='decoy',kami:kind==='kami',hyper:kind==='hyper'},steps=[];
    const inputs=[{position:[12,30,-9],yaw:1.2,delta:.016,snap:true},
      {position:[13,31,-8],yaw:3.12,delta:.016,snap:false},
      {position:[14,31.5,-7],yaw:-3.12,delta:.1,snap:false},
      {position:[14,31.5,-7],yaw:0,delta:0,snap:false},
      {position:[14,31.5,-7],yaw:0,delta:.1,snap:false},
      {position:[14,31.5005,-7],yaw:-8,delta:.1,snap:false},
      {position:[14,31.5015,-7],yaw:12,delta:.1,snap:false},
      {position:[14,25,-7],yaw:Math.PI/2,delta:.25,snap:false},
      {position:[14,20,-7],yaw:-Math.PI/2,delta:.3,snap:true},
      {position:[10,40,7],yaw:-Math.PI,delta:2,snap:false}];
    for(const input of inputs) {
      entity.ry=input.yaw;
      const previous=mesh.position.clone(),[nx,ny,nz]=input.position;
      pose(entity,mesh.position,nx,ny,nz,previous.x,previous.z,mesh.rotation.y,input.snap,input.delta,10,d.lerpFPS);
      mesh.position.fromArray(input.position);mesh.updateMatrix();
      steps.push({...input,rotation:mesh.rotation.toArray().slice(0,3),matrix:mesh.matrix.toArray()});
    }
    result.push({kind,initial,steps});
  }
  return result;
}
