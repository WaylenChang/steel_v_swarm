export function instrumentPetalCapture(biomes, grabFn) {
  const original = grabFn(biomes,'buildPetals');
  const signature = 'function buildPetals(group, terrain, items, season, mode, dynamics, gseed) {';
  const begin = 'const { parts } = planPetalFields(crowns, {';
  const low = 'low: lowPower(),';
  const seq = 'const seq = [0, 0, 0];';
  const empty = 'if (!parts.length) return 0;';
  const invoke = 'const petalsBuilt = petalMode ? buildPetals(group, terrain, items, season, petalMode, dynamics, gseed) : 0;';
  if (![signature,begin,low,seq,empty,'t += dt;'].every(seam=>original.includes(seam)) || !biomes.includes(invoke))
    throw new Error('Missing original petal capture seam');
  const instrumented = original.replace(signature,signature.replace('gseed)', 'gseed, nativeLow = lowPower())')
      + '\n  const nativeCapture = group.userData.nativePetals = {season,mode,low:nativeLow,constants:{...PETAL},parts:[],meshes:[]};')
    .replace(low,'low: nativeLow,')
    .replace(empty,'nativeCapture.parts = parts;\n  '+empty)
    .replace(seq,'nativeCapture.meshes = meshes;\n  '+seq)
    .replace('t += dt;', 't += dt; nativeCapture.time = t;');
  return biomes.replace(original,instrumented).replace(invoke,
    'const petalsBuilt = (() => {\n    let actual = 0;\n    for (const low of [false,true]) {\n'
    + '      const variant = new THREE.Group(); group.add(variant);\n'
    + '      if (!petalMode) { variant.userData.nativePetals = {season,mode:null,low,constants:{...PETAL},parts:[],meshes:[]}; continue; }\n'
    + '      const callbacks = [];\n'
    + '      const built = buildPetals(variant,terrain,items,season,petalMode,callbacks,gseed,low);\n'
    + '      if (low === lowPower()) { actual = built; dynamics.push(...callbacks); }\n'
    + '    }\n    return actual;\n  })();');
}

export function capturePetalBundle(group) {
  const variants = [], meshes = [];
  group.traverse(node=>{if(node.userData.nativePetals) variants.push(node.userData.nativePetals);});
  if (variants.length !== 2 || new Set(variants.map(row=>row.low)).size !== 2)
    throw new Error('Missing original full/low-power petal rosters');
  return {petalsCaptured:true,petals:{variants:variants.map(source=>{
    const batches = source.meshes.flatMap((mesh,tone)=>{
      if (!mesh) return [];
      const id = meshes.length+1;
      meshes.push(mesh);mesh.userData.nativePetalMesh=id;
      return [{id,tone,count:mesh.count,priority:mesh.renderOrder}];
    });
    const parts = source.parts.map(part=>({...part}));
    const scalar = ['cx','cz','y0','h','r','a','w','vy','p1','p2','ax','ay','az','sp','ang','sz','ox','oz','oy','y'];
    if (!['spring','summer','autumn','winter'].includes(source.season) || ![null,'bloom','leaf'].includes(source.mode)
      || parts.some(part=>!scalar.every(key=>Number.isFinite(part[key]))
        || !batches.some(batch=>batch.tone===part.tone&&Number.isInteger(part.mi)&&part.mi>=0&&part.mi<batch.count)))
      throw new Error('Invalid original petal state/mesh capture');
    return {season:source.season,mode:source.mode,low:source.low,time:source.time||0,constants:{...source.constants},parts,batches};
  })}};
}
