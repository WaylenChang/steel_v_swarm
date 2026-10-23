import {captureWildlifeBundle} from './wildlife_capture.mjs';

export function wildlifeDensityReferences({THREE,catalogProgram,originalProgram,buildOf,terrain,anchors,blockers,mode}) {
  terrain.waterY=0;
  const root=new THREE.Group(),calls=[];
  buildOf(catalogProgram,calls,()=>1)(root,terrain,[],{anchors,low:false,blockers});
  const source=captureWildlifeBundle(root).wildlife;
  const matrices=mesh=>{
    const matrix=new THREE.Matrix4();
    return Array.from({length:mesh.count},(_,i)=>{mesh.getMatrixAt(i,matrix);return matrix.toArray();});
  };
  const catalogMeshes=[];
  root.traverse(node=>{if(node.userData.nativeWildlifeMesh)catalogMeshes.push({id:node.userData.nativeWildlifeMesh,frames:matrices(node)});});
  const snapshot=rosters=>rosters.map(({root})=>{
    const original=root.userData.nativeWildlife;
    return {low:original.low,states:original.states.map(({st})=>({count:st.count,seed:st.seed,kind:st.kind,t:st.t,
      pos:Array.from(st.pos),vel:Array.from(st.vel),spd:Array.from(st.spd),off:Array.from(st.off),wing:Array.from(st.wing)})),
      batches:original.batches.map(batch=>({species:batch.species,body:matrices(batch.body),limbs:batch.limbs.map(limb=>matrices(limb.mesh))}))};
  });
  const all=value=>Object.fromEntries(['birds','fish','cats','dogs','wildlife'].map(key=>[key,value]));
  const cases=[];
  for(const densities of [all(0),all(1),all(1.5),all(2),{...all(0),wildlife:1.5},
    {birds:0,fish:.5,cats:1.5,dogs:1.5,wildlife:1.5},{birds:.01,fish:.5,cats:.1666666667,dogs:1,wildlife:0},
    {birds:1.5,fish:0,cats:0,dogs:0,wildlife:0}]) {
    terrain.waterY=0;
    const target=new THREE.Group(),expected=[];
    buildOf(originalProgram,expected,key=>densities[key]??0)(target,terrain,[],{anchors,low:false,blockers});
    const initial=snapshot(expected),frames=[];
    for(const [delta,time,activity,waterY] of [[.016,.016,1,0],[.25,.266,.15,12],[4,.516,.5,0],[-1,.6,1,0],[.016,12,1,0]]) {
      terrain.waterY=waterY;
      for(const entry of expected)entry.result.update(delta,time,{activity});
      frames.push({delta,time,activity,waterY,variants:snapshot(expected)});
    }
    cases.push({densities,initial,frames});
  }
  return {mode,source,catalogMeshes,cases};
}
