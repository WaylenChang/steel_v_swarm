export function instrumentSceneryMotion(biomes, parts) {
  const joint = 'joints.push({ pivot, motion });';
  const edge = 'pivot.add(mesh); root.add(pivot); group.add(root);';
  const waterfall = 'let t = Math.random() * 10;';
  if (!parts.includes(joint) || !biomes.includes(edge) || !biomes.includes(waterfall))
    throw new Error('Missing original scenery motion capture seam');
  return {
    parts:parts.replace(joint, "pivot.userData.nativeSceneryMotion = {kind:'part',motion:{...motion,phase:motion.phase||0,amplitude:motion.amplitude??0.08}};\n    " + joint),
    biomes:biomes.replace(edge, edge + '\n      pivot.userData.nativeSceneryMotion = {kind:mot.kind,phase:mot.phase,baseY:py,fry:s.fry,constants:{...EDGE_MOTION}};')
      .replace(waterfall, waterfall + "\n    sheets.forEach((sheet,index)=>sheet.userData.nativeSceneryMotion={kind:'waterfall_sheet',index,start:t,range:10,clockGroup:g.uuid});\n    foam.userData.nativeSceneryMotion={kind:'waterfall_foam',start:t,range:10,clockGroup:g.uuid};"),
  };
}

export function captureSceneryMotion(group) {
  const motions = [], nodes = [], clocks = new Map();
  group.updateMatrixWorld(true);
  group.traverse(node=>{
    if (!node.userData.nativeSceneryMotion) return;
    node.userData.nativeMotionId = nodes.length + 1;
    nodes.push(node);
  });
  for (const node of nodes) {
    const spec = node.userData.nativeSceneryMotion;
    if (!['part','rotor','float','machine','smoke','dust','waterfall_sheet','waterfall_foam','cruiser','vessel_wake','moored'].includes(spec.kind))
      throw new Error('Unsupported original scenery motion: '+spec.kind);
    if (spec.kind === 'part') {
      const motion = spec.motion;
      if (!motion || !['spin','swing'].includes(motion.kind) || !['x','y','z'].includes(motion.axis)
        || ![motion.speed,motion.phase||0,motion.amplitude??.08].every(Number.isFinite))
        throw new Error('Invalid original articulated scenery motion');
    } else if (['cruiser','vessel_wake','moored'].includes(spec.kind)) {
      if (!Number.isFinite(spec.phase) || Object.values(spec).some(value=>typeof value==='number'&&!Number.isFinite(value))
        || (spec.kind==='cruiser' && !(spec.radius>0))) throw new Error('Invalid original vessel motion');
    } else if (spec.kind.startsWith('waterfall_')) {
      if (![spec.start,spec.range].every(Number.isFinite) || spec.start < 0 || spec.start >= spec.range
        || !spec.clockGroup || (spec.kind === 'waterfall_sheet' && ![0,1].includes(spec.index)))
        throw new Error('Invalid original waterfall motion');
      if (!clocks.has(spec.clockGroup)) clocks.set(spec.clockGroup,clocks.size+1);
    } else if (![spec.phase,spec.baseY,spec.fry,...Object.values(spec.constants||{})].every(Number.isFinite)
      || !spec.constants || !Object.keys(spec.constants).length) throw new Error('Invalid original edge scenery motion');
    let parent = node.parent;
    while (parent && !parent.userData.nativeMotionId && !parent.userData.nativeTrainId) parent=parent.parent;
    const anchor = node.parent.matrixWorld.clone();
    if (parent) anchor.premultiply(parent.matrixWorld.clone().invert());
    const values = [...anchor.elements,...node.position.toArray(),...node.rotation.toArray().slice(0,3),...node.scale.toArray()];
    if (!values.every(Number.isFinite)) throw new Error('Invalid original scenery motion transform');
    motions.push({...spec,...(spec.clockGroup?{clockGroup:clocks.get(spec.clockGroup)}:{}),id:node.userData.nativeMotionId,
      parentMotion:parent?.userData.nativeMotionId||0,parentTrain:parent?.userData.nativeTrainId||0,
      anchor:anchor.toArray(),position:node.position.toArray(),rotation:node.rotation.toArray().slice(0,3),
      order:node.rotation.order,scale:node.scale.toArray()});
  }
  return {motionsCaptured:true,motions};
}
