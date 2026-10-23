export function instrumentWildlifeCapture(biomes, render, ground, catalog = false) {
  const populationStart = 'const populations = [';
  const construct = 'const wildlife = buildWildlifeBatches(group, populations, { probe, bounds, waterY: terrain.waterY, validAt, wetAt, low });';
  const returnRender = 'return { total, batches, update };';
  const footprint = 'add,\n    near(foot, gap = 0) {';
  if (![populationStart,construct].every(seam=>biomes.includes(seam)) || !render.includes(returnRender)
    || !render.includes('tailAngle }') || !ground.includes(footprint))
    throw new Error('Missing original wildlife/footprint capture seam');
  const densityLimit=/route\.count \* Math\.min\(([\d.]+), density\)/.exec(render);
  if(!densityLimit)throw new Error('Missing original wildlife density cap');
  const result = {
    ground:ground.replace(footprint,'nativeGrid: grid, nativeCell: cell, '+footprint),
    render:render.replace('tailAngle }', 'tailAngle, specSpringPS }').replace(returnRender,
      'group.userData.nativeWildlife = {states:states.map(state=>({...state,spring:specSpringPS(state.st.spec)})),batches,low,bounds,waterY,stride:flockDiv,budget,densityLimit:'+Number(densityLimit[1])+'};\n  '+returnRender),
    biomes:biomes.replace(populationStart,'const populationsOf = low => {\n  '+populationStart)
      .replace(construct,'return populations;\n  };\n  const populations = populationsOf(low);\n'
        + 'const variant = new THREE.Group(); group.add(variant);\n'
        + construct.replace('buildWildlifeBatches(group,','buildWildlifeBatches(variant,')
        + '\n  variant.userData.nativeWildlife.occupied = occupied;'
        + '\n  const alternate = new THREE.Group(); group.add(alternate);'
        + '\n  buildWildlifeBatches(alternate, populationsOf(!low), {probe,bounds,waterY:terrain.waterY,validAt,wetAt,low:!low});'
        + '\n  alternate.userData.nativeWildlife.occupied = occupied;'),
  };
  if(catalog) {
    const seams=["const dens = visualPref('birds');","const fishDens = visualPref('fish'), catDens = visualPref('cats'), dogDens = visualPref('dogs');","const smallDens = visualPref('wildlife');"];
    if(!seams.every(seam=>result.biomes.includes(seam)))throw new Error('Missing original wildlife catalog preference seams');
    result.biomes=result.biomes.replace(seams[0],'const dens = Infinity;')
      .replace(seams[1],'const fishDens = Infinity, catDens = Infinity, dogDens = Infinity;')
      .replace(seams[2],'const smallDens = Infinity;')
      .replace('alternate.userData.nativeWildlife.occupied = occupied;',`alternate.userData.nativeWildlife.occupied = occupied;
  variant.userData.nativeWildlife.catalogCaptured = true;
  alternate.userData.nativeWildlife.catalogCaptured = true;
  for(const nativeLow of [false,true]) {
    const planned = populationsOf(nativeLow);
    for(let order=0;order<planned.length;order++) {
      const population=planned[order];
      const preference=({bird:'birds',fish:'fish',cat:'cats',dog:'dogs'})[population.species] || 'wildlife';
      for(let routeIndex=0;routeIndex<population.routes.length;routeIndex++) {
        const route=population.routes[routeIndex], unit=new THREE.Group();group.add(unit);
        buildWildlifeBatches(unit,[{...population,density:Infinity,routes:[route]}],
          {probe,bounds,waterY:terrain.waterY,validAt,wetAt,low:nativeLow});
        unit.userData.nativeWildlife.occupied=occupied;
        unit.userData.nativeWildlife.catalog={species:population.species,preference,order,routeIndex,baseCount:route.count};
      }
    }
  }`);
  }
  return result;
}

export function captureWildlifeBundle(group) {
  const variants = [], catalogs = [], meshes = [], bundles = [];
  group.traverse(node=>{if(node.userData.nativeWildlife) bundles.push(node.userData.nativeWildlife);});
  const defaults=bundles.filter(bundle=>!bundle.catalog);
  if (defaults.length !== 2 || new Set(defaults.map(bundle=>bundle.low)).size !== 2)
    throw new Error('Missing original full/low-power wildlife rosters');
  let footprints = null;
  for (const bundle of bundles) {
    if (![2,4].includes(bundle.stride) || !Number.isInteger(bundle.budget) || bundle.budget<=0 || !(bundle.densityLimit>0) || !Number.isFinite(bundle.densityLimit)
      || !['minX','maxX','minZ','maxZ'].every(key=>Number.isFinite(bundle.bounds?.[key]))
      || (bundle.waterY != null && !Number.isFinite(bundle.waterY))) throw new Error('Invalid original wildlife bounds/stride/water level');
    if (!bundle.occupied?.nativeGrid || !(bundle.occupied.nativeCell > 0)) throw new Error('Missing original wildlife habitat footprint index');
    if (!footprints) {
      const feet = [], ids = new Map(), grid = {};
      for (const [key,rows] of bundle.occupied.nativeGrid) grid[key]=rows.map(foot=>{
        if (!ids.has(foot)) {ids.set(foot,feet.length);feet.push({...foot});}
        return ids.get(foot);
      });
      footprints={cell:bundle.occupied.nativeCell,feet,grid};
    }
    const states = bundle.states.map(({st,spring})=>({
      pts:Array.from(st.pts),n:st.n,len:st.len,kind:st.kind,seed:st.seed,count:st.count,t:st.t,spec:{...st.spec},
      pos:Array.from(st.pos),vel:Array.from(st.vel),spd:Array.from(st.spd),off:Array.from(st.off),wing:Array.from(st.wing),spring,
    }));
    const tag = mesh=>{
      const id = meshes.length+1;
      mesh.userData.nativeWildlifeMesh=id;
      meshes.push(mesh);
      return id;
    };
    const batches = bundle.batches.map(batch=>({species:batch.species,
      animals:batch.animals.map(({st,i})=>({state:bundle.states.findIndex(state=>state.st===st),i})),
      body:tag(batch.body),limbs:batch.limbs.map(limb=>({mesh:tag(limb.mesh),pivot:limb.pivot.toArray(),rest:limb.rest.toArray(),
        wing:limb.part.wing||0,tail:!!limb.part.tail,leg:limb.part.leg||0})),
    }));
    if (states.some(state=>!Number.isInteger(state.count) || state.count<=0 || !Number.isInteger(state.n) || state.n<=0
      || state.pos.length!==state.count*3 || state.vel.length!==state.count*3 || state.pts.length!==state.n*3 || !(state.len>0)
      || !Number.isFinite(state.spring) || [state.spd,state.off,state.wing].some(values=>values.length!==state.count)
      || ![...state.pts,...state.pos,...state.vel,...state.spd,...state.off,...state.wing].every(Number.isFinite))
      || batches.some(batch=>batch.animals.some(animal=>animal.state<0))) throw new Error('Invalid original wildlife route/state capture');
    const profile={low:bundle.low,stride:bundle.stride,bounds:{...bundle.bounds},waterY:bundle.waterY,states,batches,
      budget:bundle.budget,densityLimit:bundle.densityLimit};
    if(bundle.catalog) {
      if(states.length!==1||batches.length!==1||!Number.isInteger(bundle.catalog.baseCount)||bundle.catalog.baseCount<0)
        throw new Error('Invalid original wildlife route capacity catalog');
      catalogs.push({...profile,catalog:{...bundle.catalog}});
    } else variants.push(profile);
  }
  return {wildlifeCaptured:true,wildlife:{variants,footprints,catalogCaptured:defaults.every(bundle=>bundle.catalogCaptured===true),catalogs}};
}
