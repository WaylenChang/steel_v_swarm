export function instrumentAquaticCapture(source, grabFn) {
  const patch = (name, change) => {
    const original = grabFn(source,name), modified=change(original);
    if (modified===original) throw new Error('Missing original aquatic capture seam: '+name);
    source=source.replace(original,modified);
  };
  patch('createBubbleSystem',text=>{
    const random='const rnd = mulberry32((seed ^ 0x3B881A) >>> 0);';
    const group='group: new THREE.Group(),';
    if(!text.includes(random)||!text.includes(group))throw new Error('Missing original bubble seed/group seam');
    return text.replace(random,'const nativeSeed = (seed ^ 0x3B881A) >>> 0, nativeRandom = mulberry32(nativeSeed);\n  let nativeDraws = 0;\n  const rnd = () => {nativeDraws++; return nativeRandom();};')
      .replace(group,group+'\n    nativeCapture: {kind:"bubble",particles,seed:nativeSeed,get draws(){return nativeDraws;},meshes:[{role:"water",mesh:meshWater},{role:"swamp",mesh:meshSwamp}]},');
  });
  patch('createFishSchools',text=>text.replace('group: mesh,','group: mesh,\n    nativeCapture: {kind:"fish",schools,fishPerSchool,meshes:[{role:"fish",mesh}]},'));
  patch('createJellyfishFields',text=>text.replace('group: mesh,','group: mesh,\n    nativeCapture: {kind:"jelly",jellies,meshes:[{role:"jelly",mesh}]},'));
  patch('createSuspendedDetritus',text=>text.replace('group: pts,','group: pts,\n    nativeCapture: {kind:"detritus",particles:data,seeds,positions:pos,colours:col,meshes:[{role:"detritus",mesh:pts}]},'));
  patch('createSurfaceVessels',text=>{
    const seam='  updateWaveSources();\n\n  return {';
    return text.replace(seam,`  updateWaveSources();
  for (const c of cruisers) {
    const wave = waveSources.find(source=>source.mesh===c.mesh);
    c.mesh.userData.nativeSceneryMotion = {kind:'cruiser',cx:c.cx,cz:c.cz,radius:c.radius,speed:c.speed,angle:c.angle,rotDir:c.rotDir,phase:c.phase,
      waterY:wy,minX:clampMinX,maxX:clampMaxX,minZ:clampMinZ,maxZ:clampMaxZ,wave:{length:wave.length,beam:wave.beam,speed:wave.speed}};
    if(c.wakeGroup)c.wakeGroup.userData.nativeSceneryMotion={kind:'vessel_wake',phase:c.phase};
  }
  for(const b of mooredBoats) {
    const wave=waveSources.find(source=>source.mesh===b.mesh);
    b.mesh.userData.nativeSceneryMotion={kind:'moored',baseY:b.baseY,phase:b.phase,bobAmp:b.bobAmp,frequency:AQUATIC.BOAT_BOB_FREQ,
      ...(wave?{wave:{length:wave.length,beam:wave.beam,speed:wave.speed}}:{})};
  }

  return {`);
  });
  patch('buildAquaticWorld',text=>{
    for(const name of ['bubbleSys','detritusSys','fishSys','jellySys']) {
      const seam='rootGroup.add('+name+'.group);';
      if(!text.includes(seam))throw new Error('Missing original aquatic system binding: '+name);
      text=text.replace(seam,name+'.group.userData.nativeAquatic = '+name+'.nativeCapture;\n    '+seam);
    }
    return text;
  });
  return source;
}

export function captureAquaticBundle(group, waterY) {
  const systems=[], nodes=[];
  group.traverse(node=>{if(node.userData.nativeAquatic)nodes.push(node);});
  let meshId=0;
  for(const node of nodes) {
    const source=node.userData.nativeAquatic;
    if(!['bubble','fish','jelly','detritus'].includes(source.kind))throw new Error('Unknown original aquatic system');
    const batches=source.meshes.map(({role,mesh})=>{
      const id=++meshId;
      if(mesh.isPoints)mesh.userData.nativeAquaticPoints=id;
      else mesh.userData.nativeAquaticMesh=id;
      return {role,id,count:mesh.isPoints?mesh.geometry.attributes.position.count:mesh.count};
    });
    const result={kind:source.kind,batches};
    if(source.kind==='bubble')Object.assign(result,{seed:source.seed,draws:source.draws,particles:source.particles.map(part=>({...part}))});
    if(source.kind==='fish')Object.assign(result,{schools:source.schools.map(school=>({...school})),fishPerSchool:source.fishPerSchool});
    if(source.kind==='jelly')result.jellies=source.jellies.map(jelly=>({...jelly}));
    if(source.kind==='detritus') {
      const material=source.meshes[0].mesh.material;
      if(!material.isPointsMaterial||material.map||material.alphaMap||material.alphaTest||material.blending!==1
        ||!material.transparent||material.depthWrite||!material.depthTest||!material.fog||!material.toneMapped)
        throw new Error('Unsupported original aquatic Points material');
      Object.assign(result,{particles:source.particles.map(part=>({...part})),seeds:Array.from(source.seeds),
        positions:Array.from(source.positions),colours:Array.from(source.colours),
        material:{size:material.size,opacity:material.opacity,colour:material.color.toArray(),vertexColors:material.vertexColors,
          sizeAttenuation:material.sizeAttenuation}});
      if(![result.material.size,result.material.opacity,...result.material.colour].every(Number.isFinite))
        throw new Error('Invalid original aquatic point size/colour/opacity');
    }
    const finite=(row,keys)=>keys.every(key=>Number.isFinite(row[key]));
    if(source.kind==='bubble' && (!Number.isInteger(result.seed)||!Number.isInteger(result.draws)||result.draws<0
      || result.particles.some(part=>!finite(part,['x','z','y','floorY','surfaceY','baseR'])
        || (part.surfaceY>part.floorY&&!finite(part,['wobblePh','wobbleSpd','riseSpd'])))))
      throw new Error('Invalid original aquatic bubble state/RNG capture');
    if(source.kind==='fish' && (!Number.isInteger(result.fishPerSchool)||result.fishPerSchool<=0
      || result.schools.some(school=>!finite(school,['cx','cz','radius','swimDepth','speed','rotDir','phaseOff'])||school.radius<=0)
      || result.schools.length*result.fishPerSchool>batches[0].count)) throw new Error('Invalid original aquatic fish school capture');
    if(source.kind==='jelly' && (result.jellies.length>batches[0].count
      || result.jellies.some(jelly=>!finite(jelly,['x','z','baseY','scale','pulseSpd','pulsePh','driftR']))))
      throw new Error('Invalid original aquatic jelly capture');
    if(source.kind==='detritus' && (result.positions.length!==result.particles.length*3||result.colours.length!==result.positions.length
      ||result.seeds.length!==result.particles.length||![...result.positions,...result.colours,...result.seeds].every(Number.isFinite)
      ||result.particles.some(part=>!finite(part,['x','z','y','floorY','surfaceY','spd']))))
      throw new Error('Invalid original suspended detritus capture');
    systems.push(result);
  }
  if(waterY!=null && (systems.length!==4 || new Set(systems.map(system=>system.kind)).size!==4))
    throw new Error('Missing original water-bearing aquatic system roster');
  return {aquaticsCaptured:true,aquatics:{systems}};
}
