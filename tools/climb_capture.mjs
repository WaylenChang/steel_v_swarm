// Browser-side adapter for a completed original buildBiomes group. A road-only
// group deliberately cannot certify climb coverage or invent obstacle routes.
export function captureClimbBundle(group, captureMesh, arrowColors) {
  if (!Array.isArray(group.userData.climbs)) return {climbsCaptured: false, climbFacilitiesCaptured: false, climbs: []};
  const routes = group.userData.climbs;
  const facility = group.getObjectByName('climbRoutes');
  if (routes.length && !facility) throw new Error('Original climb routes have no matching facility graph');
  const fields = ['x','z','y0','y1','nx','nz','bx','bz','tx','tz','vy0','vy1','fx','fz','gap','arm'];
  const climbs = routes.map((route, index) => {
    if (!route.b || !group.userData.blockers?.includes(route.b) || (route.link && !group.userData.blockers.includes(route.link)))
      throw new Error('Original climb route has no live source support');
    const result = {id: index + 1, kind: route.kind};
    for (const key of fields) if (route[key] != null) {
      if (!Number.isFinite(route[key])) throw new Error('Non-finite original climb field: ' + key);
      result[key] = route[key];
    }
    for (const [key, blocker] of [['blocker', route.b], ['link', route.link]]) if (blocker)
      result[key] = Object.fromEntries(Object.entries(blocker).filter(([, value]) => typeof value === 'string' || typeof value === 'boolean' || Number.isFinite(value)));
    return result;
  });
  facility?.traverse(node => {
    if (!node.isMesh) return;
    const material = node.material;
    let arrow = '';
    if (material?.isMeshBasicMaterial) {
      if (material.color.getHex() === arrowColors.UP) arrow = 'up';
      else if (material.color.getHex() === arrowColors.DOWN) arrow = 'down';
      else throw new Error('Unexpected original climb arrow palette');
    }
    captureMesh(node, 'Climb', false, {sourceClimb: true, climbArrow: arrow});
  });
  return {climbsCaptured: true, climbFacilitiesCaptured: true, climbs};
}
