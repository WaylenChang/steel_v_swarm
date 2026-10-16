// Offline expectations use the shipped Three implementation with native-width inputs.
export function quaternionReferences(THREE) {
  for(const method of ['slerp','setFromUnitVectors'])
    if(!THREE.Quaternion.prototype[method].toString().includes('Number.EPSILON'))
      throw new Error('Original quaternion epsilon rule changed: '+method);
  const q = values => new THREE.Quaternion(...values.map(Math.fround));
  const vector = values => new THREE.Vector3(...values.map(Math.fround));
  const quaternionOps=[],quaternionSlerps=[],quaternionDirections=[],quaternionMatrices=[],quaternionWorlds=[];
  const samples=[[0,0,0,0],[0,0,0,1],[0,0,0,-1],[.2,-.1,.4,.8],[.5,.5,.5,.5],[.6,0,0,.8]];
  for(const first of samples)for(const second of samples) {
    const a=q(first),b=q(second),point=vector([.3,-2,4]);
    quaternionOps.push({first:a.toArray(),second:b.toArray(),point:point.toArray(),normalized:a.clone().normalize().toArray(),
      inverse:a.clone().invert().toArray(),product:a.clone().multiply(b).toArray(),
      rotated:point.clone().applyQuaternion(a).toArray(),matrix:new THREE.Matrix4().makeRotationFromQuaternion(a).toArray()});
    for(const weight of [-.2,0,.2,.5,1,1.2])quaternionSlerps.push({first:a.toArray(),second:b.toArray(),weight,result:a.clone().slerp(b,weight).toArray()});
  }
  for(const first of [[0,1,0],[1,0,0],[0,0,1],[1,2,3]])for(const second of [[0,1,0],[0,-1,0],[-1,0,0],[0,0,-1],[1e-8,-1,0],[-1,-2,-3]]) {
    const a=vector(new THREE.Vector3(...first).normalize().toArray()),b=vector(new THREE.Vector3(...second).normalize().toArray());
    quaternionDirections.push({first:a.toArray(),second:b.toArray(),result:new THREE.Quaternion().setFromUnitVectors(a,b).toArray()});
  }
  const matrices=[];
  for(const angles of [[0,0,0],[Math.PI,0,0],[0,Math.PI,0],[0,0,Math.PI],[.7,-1.2,.3]])
    for(const scale of [[1,2,3],[-1,2,3],[1,-2,3],[1,2,-3],[-1,-2,3],[1e-8,2,3],[0,1,1]])
      matrices.push(new THREE.Matrix4().compose(new THREE.Vector3(3,-4,5),new THREE.Quaternion().setFromEuler(new THREE.Euler(...angles)),new THREE.Vector3(...scale)));
  matrices.push(new THREE.Matrix4().set(1,.4,.2,3,0,2,.3,-4,0,0,3,5,0,0,0,1),
    new THREE.Matrix4().set(-1,.4,.2,3,0,2,.3,-4,0,0,3,5,0,0,0,1));
  for(const source of matrices) {
    const matrix=new THREE.Matrix4().fromArray(source.toArray().map(Math.fround)),rotation=new THREE.Quaternion();
    matrix.decompose(new THREE.Vector3(),rotation,new THREE.Vector3());
    quaternionMatrices.push({matrix:matrix.toArray(),result:rotation.toArray().map(value=>Number.isFinite(value)?value:String(value))});
  }
  const record = node=>({p:node.position.toArray(),q:node.quaternion.toArray(),s:node.scale.toArray(),
    r:[node.rotation.x,node.rotation.y,node.rotation.z],order:node.rotation.order});
  for(const reflected of [false,true]) {
    const root=new THREE.Object3D(),parent=new THREE.Object3D(),child=new THREE.Object3D();root.add(parent);parent.add(child);
    const nodes=[root,parent,child];
    for(const [index,node]of nodes.entries()) {
      node.position.fromArray([.3+index,1.2-index,-.4].map(Math.fround));
      node.rotation.order=['XYZ','YXZ','ZXY'][index];node.rotation.set(.12+index*.2,-.3,.4);
      node.quaternion.fromArray(node.quaternion.toArray().map(Math.fround));
      node.scale.fromArray([reflected&&index===1?-1:1,1.5+index,.7].map(Math.fround));
    }
    root.updateMatrixWorld(true);
    quaternionWorlds.push({nodes:nodes.map(record),result:nodes.map(node=>({matrix:node.matrixWorld.toArray(),quaternion:node.getWorldQuaternion(new THREE.Quaternion()).toArray()}))});
  }
  return {numberEpsilon:Number.EPSILON,fixtures:{quaternionOps,quaternionSlerps,quaternionDirections,quaternionMatrices,quaternionWorlds}};
}
