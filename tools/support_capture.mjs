// Preserve completed source scenery supports; road-only groups cannot certify them.
export function prepareSceneryCapture(group, detachBuilding) {
  const data = group.userData;
  if (!(data.mapBuildings instanceof Map) || !Array.isArray(data.nativeCampBuildingMeshes) || !Array.isArray(data.nativeCampLandmarks))
    throw new Error('Missing original scenery ownership/clearance roster');
  for (const record of data.mapBuildings.values()) {
    const root = detachBuilding(record);
    root.userData.nativeBuildingKey = record.key;
  }
  for (const node of data.nativeCampBuildingMeshes) if (node.isInstancedMesh)
    node.userData.nativeCampBuildingBatch = true;
  for (const landmark of data.nativeCampLandmarks) if (!landmark.g.userData.buildingKey)
    landmark.g.userData.nativeCampLandmark = {x:landmark.x,z:landmark.z,r:landmark.r};
}

export function captureSupportBundle(group, THREE) {
  const data = group.userData;
  if (!Array.isArray(data.blockers) || !Array.isArray(data.roofPlatforms) || !(data.mapBuildings instanceof Map))
    return {supportsCaptured: false, roofPlatforms: [], sourceBuildings: [], supportBlockers: []};
  const supportBlockers = data.blockers.map(blocker => {
    const fields = ['x','z','y','h',...(blocker.hw2 != null ? ['hw2','hd2','ry'] : ['r'])];
    if (fields.some(key=>!Number.isFinite(blocker[key]))) throw new Error('Invalid original scenery blocker');
    return Object.fromEntries(Object.entries(blocker).filter(([,value])=>typeof value === 'string' || typeof value === 'boolean' || Number.isFinite(value)));
  });
  const roofPlatforms = data.roofPlatforms.map(platform => {
    if (!Number.isFinite(platform.y) || !platform.bounds || !Array.isArray(platform.outer) || platform.outer.length < 3)
      throw new Error('Invalid original roof platform');
    const rings = [platform.outer, ...(platform.holes || [])].map(ring => ring.map(point => {
      if (point.length !== 2 || !point.every(Number.isFinite)) throw new Error('Invalid original roof polygon');
      return point.slice();
    }));
    if (rings.some(ring=>ring.length < 3) || ['minX','maxX','minZ','maxZ'].some(key=>!Number.isFinite(platform.bounds[key])))
      throw new Error('Invalid original roof rings/bounds');
    // ShapeUtils removes closing duplicates before indexing its flattened rings.
    const triangulationRings = rings.map(ring=>ring.length > 1 && ring[0][0] === ring.at(-1)[0] && ring[0][1] === ring.at(-1)[1] ? ring.slice(0,-1) : ring.slice());
    const points = triangulationRings.flat();
    const triangles = THREE.ShapeUtils.triangulateShape(triangulationRings[0].map(p=>new THREE.Vector2(...p)),
      triangulationRings.slice(1).map(ring=>ring.map(p=>new THREE.Vector2(...p))));
    if (!triangles.length) throw new Error('Original roof polygon cannot be triangulated');
    return {platform: platform.platform, active: platform.active !== false,
      buildingKey: platform.buildingKey || '', sourceId: platform.sourceId, kind: platform.kind,
      outer: rings[0], holes: rings.slice(1), y: platform.y, bounds: {...platform.bounds},
      faces: triangles.flatMap(triangle=>triangle.flatMap(index=>[points[index][0],platform.y,points[index][1]]))};
  });
  const sourceBuildings = Array.from(data.mapBuildings.values(), record=>({key:record.key, id:record.id,
    max:record.max, bounds:{...record.bounds}}));
  return {supportsCaptured: true, roofPlatforms, sourceBuildings, supportBlockers};
}
