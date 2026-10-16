// Runs in the source browser; each stage calls the original shipped pose methods.
export function captureAnatomicalReferences({key,create,form,graphOf,snapshot,anatomyHelpers,gaitMethods,disposeTree}) {
  const model=create(),owner=model.userData.morph?.[form]??model.userData.rig;
  const pose=owner.anatomical,graph=graphOf(model),before=new Map();snapshot(graph,before,true);
  const feet=new Map(pose.feet.map(node=>[node,node.position.clone()]));
  const inputs=[{aim:0,slot:'light',blend:1,now:10},{aim:.00001,slot:'light',blend:1,now:10.01},
    {aim:.4,slot:'light',blend:1,now:10.1,root:[.1,.7,-.1]},{aim:1,slot:'light',blend:1,now:10.2},
    {aim:1,slot:'heavy',blend:1,now:10.3},{aim:1,slot:'missing',blend:1,now:10.4},
    {aim:1,slot:'light',blend:0,now:10.5},{aim:1,slot:'heavy',blend:.35,now:10.6},
    {aim:.4,slot:'light',blend:1,now:10.7,floor:3},{aim:.95,slot:'heavy',blend:1,now:10.8,floor:3},
    {aim:0,slot:'light',blend:1,now:11,scale:[-1,1.2,.8]},
    {aim:.6,slot:'heavy',blend:.6,now:11.1,shared:{_fireAim:.3,_aimH:1,_aimSlot:'light'}}];
  if(owner.hairFlick) {
    const duration=owner.hairFlick.pluckDuration,gap=owner.hairFlick.burstGap;
    for(const phase of [0,.4,.999999,1,1.2]) {
      const now=30+phase*duration;
      inputs.push({aim:1,slot:'light',blend:1,now,hair:{startedAt:30,firedAt:now-.01}});
    }
    inputs.push({aim:0,slot:'light',blend:1,now:32,hair:{startedAt:30,firedAt:32-gap-.000001}});
  }
  if(owner.archery)for(const age of [.259999,.26,.31,.459999,.46])
    inputs.push({aim:1,slot:'light',blend:1,now:40+age,age});
  const steps=[];
  for(const [index,input]of inputs.entries()) {
    anatomyHelpers.resetAnatomicalPose(owner);
    const resetNodes=snapshot(graph,before,true),resetApplied=pose.applied,updates=[];
    if(input.root){model.rotation.set(...input.root);updates.push({id:graph.ids.get(model),rotation:input.root});}
    if(input.scale){model.scale.fromArray(input.scale);updates.push({id:graph.ids.get(model),scale:input.scale});}
    for(const node of new Set([...pose.body,pose.head,pose.neck].filter(Boolean))) {
      node.rotation.x+=Math.sin(index*.7)*.06;node.rotation.z+=Math.cos(index*.8)*.04;
      updates.push({id:graph.ids.get(node),rotation:[node.rotation.x,node.rotation.y,node.rotation.z]});
    }
    for(const [node,position]of feet){node.position.copy(position);node.position.y+=input.floor||0;
      updates.push({id:graph.ids.get(node),position:node.position.toArray()});}
    const fields={_fireAim:input.aim,_bowAim:input.aim,_aimSlot:input.slot,_aimH:input.aim,_fireAge:input.age??0};
    Object.assign(owner,fields);if(input.hair)Object.assign(owner.hairFlick,input.hair);
    gaitMethods.stabilize(owner);anatomyHelpers.stepAnatomicalPose(owner,input.blend);gaitMethods.forward(owner);
    anatomyHelpers.stepHairFlick(owner,input.now);if(owner.archery)gaitMethods.archery(owner);
    anatomyHelpers.stepEquipmentPose(owner,input.shared??owner);model.updateMatrixWorld(true);
    steps.push({...input,fields,updates,resetNodes,resetApplied,applied:pose.applied,
      bases:pose.bases.map(base=>({id:graph.ids.get(base.node),q:base.q.toArray()})),nodes:snapshot(graph,before,true)});
  }
  disposeTree(model);return {key,form,steps};
}
