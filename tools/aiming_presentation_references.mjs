import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function aimingPresentationReferences(d, gameSource, source) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n/g, '\n');
  const method = name => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing aiming presentation seam: ${name}`);
    return new Function('THREE','reachRule',`return function ${text.slice(start + 1, end + 4).trimStart().slice(name.length)}`)(THREE,d.reachRule);
  };
  const skillVictims = method('_skillVictims');
  const updateGlows = method('_updateRangeGlows');
  const entries=[1,2,3].map(id=>({id,mesh:new THREE.Group(),dimH:4,dimR:1,dimTop:6,lk:false}));
  const material=new THREE.SpriteMaterial();
  const glowContext={side:'STEEL',dead:false,shopOpen:false,ents:new Map(entries.map(entry=>[entry.id,entry])),
    _curWeapon:()=>({def:d.heroWeapon('t01','light',1)}),_rgMaterial:()=>material,
    _shotVictims:()=>glowContext.shot,_skillVictims:()=>glowContext.skills,_isCasting:()=>glowContext.casting};
  const footprintGlowStates=[];
  const glowFrames=[
    {hits:[1,2,3],locked:[1],anchor:3,skills:[1,2,3],casting:true},
    {hits:[1,2,3],locked:[2],anchor:0,skills:[1,2,3],casting:true},
    {hits:[1,2,3],locked:[1,2,3],anchor:0,skills:[1,3],casting:true},
    {hits:[1,2,3],locked:[],anchor:1,skills:[1,3],casting:true},
    {hits:null,locked:[],anchor:0,skills:[1,2],casting:true},
    {hits:[1,2,3],locked:[3],anchor:2,skills:[],casting:false},
    {hits:null,locked:[],anchor:0,skills:[],casting:false},
  ];
  for(const frame of glowFrames) {
    for(const entry of entries) entry.lk=frame.locked.includes(entry.id);
    glowContext._lockId=frame.anchor;
    glowContext.shot=frame.hits?{hits:frame.hits.map(id=>entries[id-1]),warn:false}:null;
    glowContext.skills=frame.skills.map(id=>entries[id-1]);
    glowContext.casting=frame.casting;
    glowContext._lastCastA=frame.casting?{A:{},x:0,z:0}:null;
    updateGlows.call(glowContext);
    footprintGlowStates.push({...frame,weapon:entries.filter(entry=>entry._rgGlow).map(entry=>entry.id),
      skill:entries.filter(entry=>entry._rgGlowS).map(entry=>entry.id)});
  }
  for(const entry of entries) for(const child of [...entry.mesh.children]) entry.mesh.remove(child);
  material.dispose();
  const tolerance = /const r = A.range \+ ([\d.]+)/.exec(skillVictims.toString());
  const skillStyle = /if \(skill\)[\s\S]*?color: (0x[\da-f]+),[\s\S]*?opacity: ([\d.]+)/.exec(text.slice(text.indexOf('\n  _rgMaterial(')));
  const skillSize = /Math.max\(([\d.]+), Math.max\(h, r \* 2\) \* ([\d.]+)\)/.exec(text.slice(text.indexOf('const skillHits =')));
  if (!tolerance || !skillStyle || !skillSize) throw new Error('Missing source skill glow style');
  const skillFootprints = [];
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['def', 'atk']) for (let level = 1; level <= 4; level++) {
    const ability = d.heroAbility(character, slot, level);
    const edge = Math.fround((ability.range || 0) + Number(tolerance[1]) + 1);
    for (const centre of [[0, 0, 0], [15, 90, -25]]) {
      const row = (id, flags = {}) => ({ id, side: 'SWARM', position: [centre[0], 0, centre[2]], radius: 1,
        visible: true, dead: false, garrison: false, neutral: false, ...flags });
      const targets = [row(1), row(2, { side: 'STEEL' }), row(3, { side: '' }),
        row(4, { visible: false }), row(5, { dead: true }), row(6, { garrison: true }), row(7, { neutral: true }),
        row(8, { position: [centre[0] + edge, 500, centre[2]] }),
        row(9, { position: [Math.fround(centre[0] + edge - 0.01), -500, centre[2]] }),
        row(10, { position: [Math.fround(centre[0] + edge + 0.01), 0, centre[2]] }),
        row(11, { position: [centre[0] + edge, 0, centre[2]], radius: 0 }),
        row(12, { side: 'STEEL', position: [centre[0] + edge, 0, centre[2]] })];
      const entries = targets.map(t => ({ ...t, mesh: { position: new THREE.Vector3(...t.position), visible: t.visible }, gar: t.garrison }));
      const ctx = { side: 'STEEL', pos: new THREE.Vector3(999, 0, 999), ents: new Map(entries.map(t => [t.id, t])), _hitR: t => t.radius };
      const result = skillVictims.call(ctx, ability, centre[0], centre[2]).map(t => t.id);
      skillFootprints.push({ character, slot, level, definition: ability, centre, targets, result });
    }
  }
  // The authored roster currently has self-only or zero-range skills. Exercise the original
  // advisory helper with seam inputs without enabling any unsupported gameplay producer.
  for (const target of ['self', 'enemy', 'team', 'ground']) for (const range of [0, 10]) {
    const definition = { target, range }, centre = [15, 100, -25], edge = range + Number(tolerance[1]) + 1;
    const targets = Array.from({ length: 12 }, (_, index) => ({ id: index + 1, side: 'SWARM', radius: 1,
      position: [centre[0], 0, centre[2]], visible: true, dead: false, garrison: false, neutral: false }));
    targets[1].side = 'STEEL'; targets[2].side = ''; targets[3].visible = false; targets[4].dead = true;
    targets[5].garrison = true; targets[6].neutral = true;
    targets[7].position = [centre[0] + edge, 500, centre[2]];
    targets[8].position = [Math.fround(centre[0] + edge - 0.01), -500, centre[2]];
    targets[9].position = [Math.fround(centre[0] + edge + 0.01), 0, centre[2]];
    targets[10].position = [centre[0] + edge, 0, centre[2]]; targets[10].radius = 0;
    targets[11].position = [centre[0] + edge, 0, centre[2]]; targets[11].side = 'STEEL';
    const entries = targets.map(t => ({ ...t, mesh: { position: new THREE.Vector3(...t.position), visible: t.visible }, gar: t.garrison }));
    const ctx = { side: 'STEEL', ents: new Map(entries.map(t => [t.id, t])), _hitR: t => t.radius };
    const result = skillVictims.call(ctx, definition, centre[0], centre[2]).map(t => t.id);
    skillFootprints.push({ character: 'helper', slot: target, level: 0, definition, centre, targets, result });
  }
  const vfx = (await readFile(join(source, 'public/js/vfx.js'), 'utf8')).replace(/\r\n/g, '\n');
  const start = vfx.indexOf('export function lockGlow('), end = vfx.indexOf('\n}', start);
  if (start < 0 || end < 0) throw new Error('Missing source lock glow');
  const ringInner = Number(/new THREE\.RingGeometry\(r \* ([\d.]+)/.exec(vfx.slice(start, end))?.[1]);
  if (!ringInner) throw new Error('Missing source lock ring radius seam');
  let clock = 0;
  const lockGlow = new Function('THREE', 'glowTexture', 'performance', `return ${vfx.slice(start + 7, end + 2)}`)(
    THREE, () => new THREE.Texture(), { now: () => clock });
  const lockGlowPoses = [];
  let lockRing;
  for (const dims of [{ h: 0, r: 0, top: 0 }, { h: 2, r: 0.5, top: 5 }, { h: 4, r: 1, top: 7 },
    { h: 1, r: 0.999, top: 1 }, { h: 1, r: 1.001, top: 1 }, { h: 9, r: 2, top: 8 },
    { h: 30, r: 20, top: 34 }, { h: 3, r: 10, top: -1 }]) {
    const root = new THREE.Group(), glow = lockGlow(root, 0x123456, dims);
    const [halo, ring] = glow.children;
    const radius = ring.geometry.parameters.innerRadius / ringInner;
    if (!lockRing) {
      const positions = ring.geometry.getAttribute('position');
      lockRing = { vertices: Array.from({ length: positions.count }, (_, i) => [positions.getX(i) / radius, positions.getY(i) / radius]),
        indices: [...ring.geometry.index.array] };
    }
    for (const now of [0, 0.016, 0.25, 1, 5.125, 100]) for (const flashAge of [null, 0, 0.05, 0.199, 0.2, 0.201]) {
      clock = now * 1000;
      const hitAt = flashAge == null ? -1e9 : clock - flashAge * 1000;
      glow.userData.flashAt = hitAt;
      glow.onBeforeRender();
      lockGlowPoses.push({ dimensions: { height: dims.h, radius: dims.r, top: dims.top }, now, hit_at: hitAt / 1000,
        result: { centre: halo.position.y, halo_size: halo.scale.x, halo_opacity: halo.material.opacity,
          ring_scale: ring.scale.x, ring_opacity: ring.material.opacity, ring_angle: -ring.rotation.z,
          radius } });
    }
  }
  const {grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const warningBody=grabBlock(text,"} else if (ev.e === 'lock')").slice(1,-1);
  const warnEvent = new Function('ev', 'performance', 'LOCK', warningBody);
  const visibleExpression = /this\.hud\.locked\?\.\(([^;]+)\);/.exec(text)?.[1];
  if (!visibleExpression) throw new Error('Missing source lock warning deadline seam');
  const warnVisible = new Function('now', `return ${visibleExpression};`);
  const lockWarnings = [];
  for (const event of [{ pid: 1, tpid: 2, tid: 20 }, { pid: 2, tpid: 1, tid: 10 },
    { pid: 2, tpid: 3, tid: 30 }, { pid: 1, tpid: 1, tid: 10 }, { pid: 2, tpid: null, tid: 30 }]) {
    for (const previous of [0, 12]) {
      const ctx = { youId: 1, _lockedUntil: previous, ents: new Map(), _setLockGlow: () => {} };
      warnEvent.call(ctx, event, { now: () => 10000 }, d.LOCK);
      const until = ctx._lockedUntil;
      lockWarnings.push({ event: { type: 'lock', peer: event.pid, target_peer: event.tpid || 0 },
        viewer: 1, now: 10, previous, until,
        visibility: [until - 0.001, until, until + 0.001].map(now => ({ now, result: warnVisible.call(ctx, now) })) });
    }
  }
  return { rules: { skillRangeTolerance: Number(tolerance[1]), lockRing,
    skillGlow: { color: Number(skillStyle[1]), opacity: Number(skillStyle[2]), minimumSize: Number(skillSize[1]), sizeFactor: Number(skillSize[2]) } },
    fixtures: { skillFootprints, lockGlowPoses, lockWarnings, footprintGlowStates } };
}
