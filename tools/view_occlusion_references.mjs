import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function viewOcclusionReferences(gameSource, source) {
  const { grabMethod, grabConst } = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n?/g, '\n');
  const constants = new Function(grabConst(text, 'TPS_OCCLUSION') + '\nreturn TPS_OCCLUSION')();
  const method = name => new Function('THREE', 'TPS_OCCLUSION', `return function ${grabMethod(text, name).trimStart().slice(name.length)}`)(THREE, constants);
  const updateText = grabMethod(text, '_updateViewOcclusion');
  const number = (pattern, label, body = updateText) => {
    const match = pattern.exec(body); if (!match) throw new Error('Missing original view-occlusion seam: ' + label);
    return Number(match[1]);
  };
  const rules = { ...constants,
    frameCap: number(/Math\.min\(([\d.]+), Math\.max\(0, now - p\)/, 'fade frame cap', grabMethod(text, '_stepViewFade')),
    rightEpsilon: number(/right\.lengthSq\(\) < ([\de.-]+)/, 'vertical camera right'),
    minimumSpan: number(/const span = Math\.max\(([\d.]+)/, 'minimum body span'),
    spanRatio: number(/Math\.max\(size\.x, size\.z\) \* ([\d.]+)/, 'body span ratio'),
    minimumHeight: number(/Math\.max\(size\.y, this\.selfH, ([\d.]+)\)/, 'minimum body height'),
    broadMargin: number(/const maxRange = .* \+ ([\d.]+);/, 'candidate margin'),
    minimumRay: number(/if \(dist <= ([\d.]+)\)/, 'minimum sample distance'),
    rayNear: number(/this\._viewRaycaster\.near = ([\d.]+)/, 'ray near plane'),
    heights: [0, 1, 2].map(index => number(new RegExp(`targets\\[${index}\\]\\.set\\(center.x, y0 \\+ h \\* ([\\d.]+)`), 'sample height ' + index)),
  };
  const names = ['_registerViewOccluders', '_unregisterViewOccluders', '_isViewDescendant', '_fadeViewMesh', '_restoreViewFade', '_stepViewFade', '_clearViewOcclusion', '_updateViewOcclusion'];
  const context = () => Object.assign({ _viewOcclusionMeshes: [], _viewOcclusionSet: new Set(), _viewOcclusionSkip: new Set(),
    _viewFades: new Map(), _viewOcclusionNext: 0, _viewRaycaster: new THREE.Raycaster(), viewMode: 'tps', side: 'STEEL', dead: false, selfH: 4 },
    Object.fromEntries(names.map(name => [name, method(name)])));
  const graph = root => {
    const nodes = [], materials = [], ids = new Map(), materialIds = new Map();
    root.traverse(node => {
      ids.set(node, nodes.length); node.updateMatrix();
      const row = { name: node.name, parent: ids.get(node.parent) ?? -1, matrix: node.matrix.toArray(), visible: node.visible,
        flags: Object.fromEntries(['teamRing', 'isOutline', 'noOutline', 'noViewOcclusion'].map(key => [key, !!node.userData[key]])) };
      if (node.isMesh) {
        if (node.isInstancedMesh) {
          const matrix = new THREE.Matrix4();
          row.instances = Array.from({length:node.count}, (_, index) => { node.getMatrixAt(index,matrix); return matrix.toArray(); });
        }
        row.position = Array.from(node.geometry.attributes.position.array); row.indices = Array.from(node.geometry.index?.array || []);
        row.groups = node.geometry.groups;
        row.materials = (Array.isArray(node.material) ? node.material : [node.material]).map(material => {
          if (!materialIds.has(material)) { materialIds.set(material, materials.length); materials.push({ opacity: material.opacity, transparent: material.transparent }); }
          return materialIds.get(material);
        });
      }
      nodes.push(row);
    });
    return { nodes, materials };
  };
  const state = (ctx, base) => ({ registered: ctx._viewOcclusionMeshes.map(mesh => mesh.name).sort(), next: ctx._viewOcclusionNext,
    previous: ctx._viewFadePrev ?? null, fades: [...ctx._viewFades].map(([mesh, value]) => ({ name: mesh.name, k: value.k, last_hit: value.lastHit })).sort((a, b) => a.name.localeCompare(b.name)),
    materials: [...base].flatMap(([mesh, original]) => {
      const current = Array.isArray(mesh.material) ? mesh.material : [mesh.material], materials = Array.isArray(original) ? original : [original];
      return current.map((material, index) => ({ name: mesh.name + (current.length > 1 ? ':' + index : ''), alpha: material.opacity,
        original: material === materials[index], transparent: material.transparent, depth: material.depthWrite }));
    }).sort((a, b) => a.name.localeCompare(b.name)) });
  const viewOcclusion = [];
  for (const scenario of ['ordinary', 'camera inside shell', 'mirrored wall', 'empty owner', 'no registry',
    'instanced wall', 'mixed instanced wall', 'instanced owner', 'zero instances', 'moving instances']) {
    const root = new THREE.Group(); root.name = 'world';
    const owner = new THREE.Group(); owner.name = 'owner'; root.add(owner);
    const opaque = new THREE.MeshBasicMaterial({ opacity: .8 }), glass = new THREE.MeshBasicMaterial({ transparent: true, opacity: .6 });
    const make = (name, parent, size, position, material = opaque, flags = {}, instances = null) => {
      const geometry = new THREE.BoxGeometry(...size);
      const mesh = instances ? new THREE.InstancedMesh(geometry,material,instances.length) : new THREE.Mesh(geometry, material); mesh.name = name;
      if(instances)instances.forEach((pose,index)=>mesh.setMatrixAt(index,new THREE.Matrix4().compose(
        new THREE.Vector3(...pose.position),new THREE.Quaternion().setFromEuler(new THREE.Euler(0,pose.yaw||0,0)),
        new THREE.Vector3(...(pose.scale||[1,1,1])))));
      mesh.position.fromArray(position); Object.assign(mesh.userData, flags); parent.add(mesh); return mesh;
    };
    const poses=[{position:[-.8,0,0],yaw:.2,scale:[-1,1.1,.8]},{position:[.8,0,0],yaw:-.2}];
    if (scenario !== 'empty owner') {
      const body = make('body', owner, [2, 4, 2], [0, 2, 0],opaque,{},scenario==='instanced owner'?poses:null);
      make('body outline', body, [2.1, 4.1, 2.1], [0, 0, 0], opaque, { isOutline: true });
      const hidden = make('hidden body', owner, [1, 1, 1], [1.5, .5, 0]); hidden.visible = false;
      make('ring', owner, [10, .1, 10], [0, .1, 0], glass, { teamRing: true, noViewOcclusion: true });
    }
    const instanced=['instanced wall','mixed instanced wall','zero instances','moving instances'].includes(scenario);
    const wall = make('wall', root, scenario === 'camera inside shell' ? [8, 8, 8] : [2, 6, 1], scenario === 'camera inside shell' ? [0, 4, 15] : [0, 3, 6],
      scenario==='mixed instanced wall'?[opaque,glass,opaque,glass,opaque,glass]:opaque,{},instanced?(scenario==='zero instances'?[]:poses):null);
    if (scenario === 'mirrored wall') { wall.scale.set(-1, 1.2, .8); wall.rotation.y = .3; }
    make('wall outline', wall, [2.05, 6.05, 1.05], [0, 0, 0], opaque, { isOutline: true });
    const side = make('side wall', root, [1, 5, 1], [.9, 2.5, 9]);
    const mixed = make('mixed wall', root, [1, 5, 1], [-.9, 2.5, 9], [opaque, glass, opaque, glass, opaque, glass]);
    make('glass', root, [20, 20, .1], [0, 4, 12], glass);
    make('excluded', root, [20, 20, .1], [0, 4, 11], opaque, { noViewOcclusion: true });
    const terrain = make('terrain', root, [30, 1, 30], [0, 1, 5]);
    const base = new Map(); root.traverse(mesh => { if (mesh.isMesh) base.set(mesh, mesh.material); });
    const exported = graph(root);
    const ctx = context(); ctx._viewOcclusionSkip.add(terrain);
    ctx.ents = new Map([[1, { isSelf: true, dead: false, mesh: owner }]]);
    ctx.camera = new THREE.PerspectiveCamera(68, 1.6, .5, 5000); ctx.camera.position.set(0, 4, 15); ctx.camera.lookAt(0, 2, 0);
    ctx.camera.updateMatrixWorld(true); root.updateMatrixWorld(true);
    if (scenario !== 'no registry') ctx._registerViewOccluders(root);
    const steps = [];
    for (const step of [{ now: 10 }, { now: 10.02 }, { now: 10.05 }, { now: 10.06, move: true }, { now: 10.10 },
      { now: 10.30 }, { now: 10.31 }, { now: 10.41 }, { now: 10.40 }, { now: 10.81 }, { now: 11.21 },
      { now: 11.3, return: true }, { now: 11.36 }, { now: 11.37, unregister: true }, { now: 11.4, dead: true }]) {
      const moveInstances=scenario==='moving instances';
      const shift=amount=>{
        if(moveInstances) {
          const matrix=new THREE.Matrix4();
          for(let index=0;index<wall.count;index++){wall.getMatrixAt(index,matrix);matrix.elements[12]+=amount;wall.setMatrixAt(index,matrix);}
          wall.instanceMatrix.needsUpdate=true;
        } else wall.position.x+=amount;
        side.position.x+=amount;mixed.position.x+=amount;
      };
      if (step.move) shift(500);
      if (step.return) shift(-500);
      if (step.unregister) ctx._unregisterViewOccluders(wall);
      if (step.dead) ctx.dead = true;
      root.updateMatrixWorld(true); ctx._updateViewOcclusion(step.now);
      steps.push({ ...step, moveInstances, result: state(ctx, base) });
    }
    const geometry = ctx._tpsBox && !ctx._tpsBox.isEmpty() ? { bounds: [ctx._tpsBox.min.toArray(), ctx._tpsBox.max.toArray()],
      targets: ctx._tpsTargets.map(point => point.toArray()) } : null;
    viewOcclusion.push({ name: scenario, graph: exported, owner: 'owner', skipped: ['terrain'], noRegistry: scenario === 'no registry',
      camera: ctx.camera.matrixWorld.elements.slice(), height: ctx.selfH, geometry, steps });
  }
  const viewFade = [];
  for (const initiallyCleared of [false, true]) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshBasicMaterial({ opacity: .7 })); mesh.name = 'direct fade';
    const base = new Map([[mesh, mesh.material]]), ctx = context(); if (initiallyCleared) ctx._clearViewOcclusion();
    const steps = [];
    for (const step of [{ hit: true, now: 10 }, { now: 10 }, { now: 10.02 }, { hit: true, now: 10.03 }, { now: 10.03 },
      { now: 10.13 }, { now: 10.28 }, { now: 10.28001 }, { now: 10.38 }, { now: 10.48 }, { now: 10.58 }, { now: 10.68 }]) {
      if (step.hit) { ctx._fadeViewMesh(mesh, step.now); const fade = ctx._viewFades.get(mesh); if (fade) fade.lastHit = step.now; }
      else ctx._stepViewFade(step.now);
      steps.push({ ...step, result: state(ctx, base) });
    }
    viewFade.push({ initiallyCleared, steps });
  }
  return { rules, fixtures: { viewOcclusion, viewFade } };
}
