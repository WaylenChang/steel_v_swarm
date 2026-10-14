import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Measure the actual source model graph offline; native gameplay consumes only saved scalars.
export async function modelReferences(source, gameSource, cameraProfiles) {
  const { chromiumOrNull, chromePath } = await import(pathToFileURL(join(source, 'tools/pw.mjs')).href);
  const chromium = await chromiumOrNull();
  if (!chromium) throw new Error('Model migration requires the source development Playwright runtime');
  const text = gameSource.replace(/\r\n/g, '\n');
  const start = text.indexOf('    const dimCache = _GLOBAL_UNIT_DIM_CACHE;');
  const end = text.indexOf('    const isBoss =', start);
  if (start < 0 || end <= start) throw new Error('Source spawn dimension seam missing');
  const dimensionBody = text.slice(start, end) + '\nreturn dims;';
  const poseStart = text.indexOf('      const want = reloadOff.rx +');
  const poseEnd = text.indexOf('      if (this._flashTtl != null)', poseStart);
  if (poseStart < 0 || poseEnd <= poseStart) throw new Error('Source cockpit animation seam missing');
  const poseBody = text.slice(poseStart, poseEnd) + '\nthis.gunGroup.updateMatrix(); return this.gunGroup.matrix.toArray();';
  const kickDecay = /this.weaponKick = Math.max\(0, this.weaponKick - dt \* ([\d.]+)\)/.exec(text);
  if (!kickDecay) throw new Error('Source cockpit kick decay seam missing');
  const elevationStart = text.indexOf('    fc.sup = Math.max(-0.35');
  const elevationEnd = text.indexOf(';', elevationStart);
  if (elevationStart < 0 || elevationEnd <= elevationStart) throw new Error('Source cockpit elevation seam missing');
  const elevationBody = text.slice(elevationStart, elevationEnd + 1) + '\nreturn fc.sup;';
  const flashStart = text.indexOf('        this._flashTtl -= dt;');
  const flashEnd = text.indexOf('\n      }', flashStart);
  const flashDuration = /this\._flashTtl = (0\.045);/.exec(text);
  const flashSize = /this\.flash\.scale\.setScalar\(\(([\d.]+) \+ Math.random\(\) \* ([\d.]+)\) \* \(this\._flashHeavy \? ([\d.]+) : 1\)\)/.exec(text);
  if (flashStart < 0 || flashEnd <= flashStart || !flashDuration || !flashSize) throw new Error('Source cockpit flash seam missing');
  const flashBody = text.slice(flashStart, flashEnd);
  const flashRules = {duration:Number(flashDuration[1]),minimum:Number(flashSize[1]),span:Number(flashSize[2]),heavy:Number(flashSize[3])};
  const beamColorsMatch = /this.side === 'SWARM' \? (0x[\da-f]+) : (0x[\da-f]+)/.exec(text.slice(text.indexOf('\n  _burstEchoSelf(')));
  if (!beamColorsMatch) throw new Error('Source FPV beam colors missing');
  const beamColors = {SWARM:Number(beamColorsMatch[1]),STEEL:Number(beamColorsMatch[2])};
  const method = name => {
    const begin = text.indexOf(`\n  ${name}(`), finish = text.indexOf('\n  }\n', begin);
    if (begin < 0 || finish < 0) throw new Error(`Missing source model method: ${name}`);
    return `return function ${text.slice(begin + 1, finish + 4).trimStart().slice(name.length)}`;
  };
  const browser = await chromium.launch({ headless: true, executablePath: chromePath() });
  const sourceInputs = new Set();
  try {
    const page = await browser.newPage();
    const origin = 'http://godot-models.invalid';
    await page.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.origin === origin && url.pathname === '/') return route.fulfill({ contentType: 'text/html', body:
        '<html><head><script type="importmap">{"imports":{"three":"https://unpkg.com/three@0.160.0/build/three.module.js","three/addons/":"https://unpkg.com/three@0.160.0/examples/jsm/"}}</script></head></html>' });
      if (url.pathname.endsWith('/build/three.module.js')) {
        sourceInputs.add('out/forest_review/three.module.js');
        return route.fulfill({ contentType: 'text/javascript', body: await readFile(join(source, 'out/forest_review/three.module.js')) });
      }
      const addon = /\/examples\/jsm\/(.*\.js)$/.exec(url.pathname);
      if (addon) {
        const file = 'out/forest_review/' + addon[1].replaceAll('/', '_');
        sourceInputs.add(file);
        return route.fulfill({ contentType: 'text/javascript', body: await readFile(join(source, file)) });
      }
      if (url.origin === origin && url.pathname.startsWith('/js/')) {
        sourceInputs.add('public' + url.pathname);
        return route.fulfill({ contentType: 'text/javascript', body: await readFile(join(source, 'public', url.pathname)) });
      }
      return route.abort();
    });
    await page.goto(origin);
    const result = await page.evaluate(async ({ dimensionBody, aimBody, poseBody, kickDecay, elevationBody, flashBody, flashRules, cameraProfiles, beamColors }) => {
      const THREE = await import('three');
      const d = await import('/js/data.js');
      const { makeUnit } = await import('/js/models.js');
      const { disposeTree } = await import('/js/toon.js');
      const { glowTexture, projectileMesh, stepProjectileFx } = await import('/js/vfx.js');
      const { BattleClient, COCKPIT } = await import('/js/game.js');
      const { stepCombatFx, stepLocomotion } = await import('/js/locomotion.js');
      const { fireReferenceWeapon } = await import('/js/unitMotion.js');
      const measure = new Function('THREE', 'group', 'key', 'e', 'civ', '_GLOBAL_UNIT_DIM_CACHE', dimensionBody);
      const scope = { THREE, ...d };
      const aimPoint = new Function(...Object.keys(scope), aimBody)(...Object.values(scope));
      const pose = new Function('reloadOff', '_ZERO3', poseBody);
      const elevation = new Function('fc', 'fwdY', 'BALLISTIC', elevationBody);
      const cockpitElevation = [];
      for (const velocity of [[0, 0, 0], [30, -20, 10], [30, 20, 10], [0, 80, 0], [0, -80, 0]]) {
        for (const forwardY of [-1, -.8, 0, .8, 1]) cockpitElevation.push({ velocity, forwardY,
          result: elevation({ vel: new THREE.Vector3().fromArray(velocity) }, forwardY, d.BALLISTIC) });
      }
      const geometry = { heroes: {}, units: {} }, modelCentres = [], cockpits = {}, cockpitGraphs = {}, cockpitMuzzles = [], cockpitPoses = [], cockpitVisibility = [];
      const weaponPresentation = [], authorityWeaponPoses = [], burstWeaponPoses = [], muzzleLaunches = [];
      const cockpitFlash = [], flashTick = new Function('dt','Math',flashBody);
      for (const heavy of [false,true]) for (const dt of [0,1/60,.044,.045,.046,.09]) for (const sample of [0,.5,1-Number.EPSILON]) {
        const state = {_flashTtl:flashRules.duration,_flashHeavy:heavy,flash:{visible:true,scale:new THREE.Vector3(1,1,1)}};
        const math = Object.create(Math); math.random = () => sample;
        flashTick.call(state,dt,math);
        cockpitFlash.push({heavy,dt,sample,visible:state.flash.visible,scale:state.flash.scale.toArray()});
      }
      const graphOf = (root, omitOutlines = false) => {
        const all = [], ids = new Map(), meshes = [], materials = [], textures = [];
        const meshIds = new Map(), materialIds = new Map(), textureIds = new Map();
        root.traverse(node => { if (omitOutlines && node.userData.isOutline) return; ids.set(node, all.length); all.push(node); });
        const textureOf = texture => {
          if (!texture) return -1;
          if (textureIds.has(texture)) return textureIds.get(texture);
          const image = texture.image, canvas = document.createElement('canvas');
          canvas.width = image.width; canvas.height = image.height;
          const context = canvas.getContext('2d');
          if (image.data) {
            if (!(image.data instanceof Uint8Array) || image.data.length !== image.width * image.height * 4)
              throw new Error('Unsupported cockpit data texture');
            context.putImageData(new ImageData(new Uint8ClampedArray(image.data), image.width, image.height), 0, 0);
          } else context.drawImage(image, 0, 0);
          const index = textures.length;
          textureIds.set(texture, index);
          textures.push(canvas.toDataURL('image/png').split(',')[1]);
          return index;
        };
        const materialOf = material => {
          if (materialIds.has(material)) return materialIds.get(material);
          if (!material.color || material.isShaderMaterial) throw new Error(`Unsupported cockpit material: ${material.type}`);
          const index = materials.length;
          materialIds.set(material, index);
          materials.push({ color: material.color.getHex(), opacity: material.opacity, transparent: material.transparent,
            blending: material.blending, depthTest: material.depthTest, depthWrite: material.depthWrite,
            side: material.side, unshaded: !!material.isMeshBasicMaterial, roughness: material.roughness ?? 1,
            metalness: material.metalness ?? 0, emission: material.emissive?.getHex() || 0,
            emissionIntensity: material.emissiveIntensity ?? 0, texture: textureOf(material.map),
            flipY: material.map?.flipY ?? false, repeat: material.map?.repeat.toArray() || [1, 1],
            offset: material.map?.offset.toArray() || [0, 0] });
          return index;
        };
        const meshOf = geometry => {
          if (meshIds.has(geometry)) return meshIds.get(geometry);
          const index = meshes.length;
          meshIds.set(geometry, index);
          meshes.push({ position: Array.from(geometry.attributes.position.array),
            normal: geometry.attributes.normal ? Array.from(geometry.attributes.normal.array) : [],
            uv: geometry.attributes.uv ? Array.from(geometry.attributes.uv.array) : [],
            indices: geometry.index ? Array.from(geometry.index.array) : [], groups: geometry.groups });
          return index;
        };
        const nodes = all.map((node, id) => {
          node.updateMatrix();
          const result = { id, parent: ids.get(node.parent) ?? -1, name: node.name,
            matrix: node.matrix.toArray(), visible: node.visible };
          if (node.isMesh) {
            result.mesh = meshOf(node.geometry);
            result.materials = (Array.isArray(node.material) ? node.material : [node.material]).map(materialOf);
            node.geometry.computeBoundingBox();
            const box = node.geometry.boundingBox.clone().applyMatrix4(node.matrixWorld);
            result.worldBounds = [box.min.toArray(), box.max.toArray()];
          } else if (!node.isGroup && !node.isBone && node.type !== 'Object3D') throw new Error(`Unsupported cockpit node: ${node.type}`);
          return result;
        });
        return { data: { nodes, meshes, materials, textures }, ids };
      };
      const projectileGraphs = {}, projectileProfiles = {}, projectileGeometry = [], projectileFx = [];
      const shotColors = Object.fromEntries(['STEEL','SWARM'].map(side=>[side,BattleClient.prototype._shotCols(side)]));
      for (const [character,hero] of Object.entries(d.CHARACTERS)) for (const slot of ['light','heavy']) {
        for (const side of ['STEEL','SWARM']) {
          const key = `${character}-${slot}-${side.toLowerCase()}`, definition = d.heroWeapon(character,slot,1);
          const mesh = projectileMesh(definition,{col:shotColors[side].col,hue:hero.visual?.hue ?? 0xffd27a,heavy:slot==='heavy'});
          mesh.updateMatrixWorld(true);
          const graph = graphOf(mesh,true), fx = mesh.userData.projectileFx;
          const profile = {character,slot,side,heavy:!!fx?.heavy,phase:fx?.phase || 0,
            authored:(fx?.authored || []).map(node=>graph.ids.get(node)),wake:graph.ids.get(fx?.wake) ?? -1,
            jets:(fx?.jets || []).map(jet=>({node:graph.ids.get(jet.mesh),rad:jet.rad,len:jet.len,opacity:jet.opacity,nozzle:jet.nozzle}))};
          projectileProfiles[key] = profile; projectileGraphs[key] = graph.data;
          projectileGeometry.push({key,nodes:graph.data.nodes});
          for (const age of [0,.017,.1,.5,2]) for (const speed of [-1,0,130,260,1000]) {
            stepProjectileFx(mesh,age,speed);
            projectileFx.push({key,age,speed,nodes:[...graph.ids].filter(([node])=>node.isMesh).map(([node,id])=>
              ({id,position:node.position.toArray(),scale:node.scale.toArray(),opacity:node.material.opacity}))});
          }
          disposeTree(mesh);
        }
      }
      const capture = (character, kind, side, key) => {
        const group = makeUnit(key, side, { ch: character || null, ring: true, dissolve: true }).group;
        const dims = measure(THREE, group, key, { k: kind, s: side, ch: character || null }, false, new Map());
        if (![dims.dimTop, dims.dimH, dims.dimR].every(Number.isFinite)) throw new Error(`Invalid model bounds: ${key}/${character}/${side}`);
        const result = { top: dims.dimTop, height: dims.dimH, radius: dims.dimR,
          centre: dims.dimTop - dims.dimH * .5 };
        for (const position of [[0, 0, 0], [20, 50, -30], [-100, -50, 100]]) {
          group.position.fromArray(position);
          const ent = { mesh: group, ...dims };
          modelCentres.push({ character, kind, side, position, point: aimPoint.call({}, ent).toArray(), dimensions: result });
        }
        disposeTree(group);
        return result;
      };
      for (const [character, hero] of Object.entries(d.CHARACTERS)) {
        const sides = hero.side === 'MERC' ? ['STEEL', 'SWARM'] : [hero.side];
        for (const side of sides) {
          const dimensions = capture(character, hero.kind, side, `hero:${hero.kind}`);
          if (geometry.heroes[character] && JSON.stringify(geometry.heroes[character]) !== JSON.stringify(dimensions))
            throw new Error(`Mercenary model dimensions depend on faction: ${character}`);
          geometry.heroes[character] = dimensions;
        }
        const side = hero.side === 'MERC' ? 'STEEL' : hero.side;
        const self = makeUnit(`hero:${hero.kind}`, side, { ch: character, ring: false }).group;
        const client = Object.assign(Object.create(BattleClient.prototype), {
          side, ch: character, heroKind: hero.kind, isDrone: hero.kind === 'drone', isMorph: hero.kind === 'morph',
          flight: false, aiming: false, viewMode: 'fpv', baseFov: 68,
          scene: new THREE.Scene(), camera: new THREE.PerspectiveCamera(68, 16 / 9, .5, 4000),
          wdef: { light: d.heroWeapon(character, 'light', 1), heavy: d.heroWeapon(character, 'heavy', 1) },
          ents: new Map([[1, { id: 1, isSelf: true, mesh: self }]]) });
        client._buildCockpit();
        const muzzleIds = new Map(), cachePoints = [];
        const cacheSets = Object.fromEntries(Object.entries(client._muzzles).map(([key, slots]) => [key === 'A' ? 'air' : 'ground',
          Object.fromEntries(Object.entries(slots).map(([slot, point]) => {
            if (!muzzleIds.has(point)) {muzzleIds.set(point,cachePoints.length);cachePoints.push(point.toArray());}
            return [slot,muzzleIds.get(point)];
          }))]));
        const muzzleCache = {points:cachePoints,forms:cacheSets,current:muzzleIds.get(client._muzzle)};
        client._syncCockpitWeapon();
        client.camera.updateMatrixWorld(true);
        const profile = { pivot: client._gunPivot.toArray(), lift: client._gunLift,
          drop: client._gunDrop, pull: client._gunPull, baseZ: client._gunBaseZ, forms: {}, muzzleCache };
        const emissionNodes = {};
        for (const form of hero.kind === 'morph' ? ['ground', 'air'] : ['ground']) {
          client.flight = form === 'air';
          const ports = {};
          emissionNodes[form] = {};
          for (const slot of ['light', 'heavy']) {
            client.aiming = slot === 'heavy';
            const sequence = self.userData.rig.weaponSequences[slot];
            ports[slot] = [];
            emissionNodes[form][slot] = [];
            for (let i = 0; i < sequence.entries.length; i++) {
              sequence.index = i - 1;
              client._syncCockpitWeapon();
              client.camera.updateMatrixWorld(true);
              const point = client._selfMuzzle(null, 100, slot);
              emissionNodes[form][slot].push(client._cockpitEmission(slot, true));
              ports[slot].push(client.gunGroup.worldToLocal(point.clone()).toArray());
              cockpitMuzzles.push({ character, form, slot, index: i, local: ports[slot].at(-1), point: point.toArray() });
            }
            sequence.index = -1;
          }
          profile.forms[form] = ports;
        }
        client.flight = false; client.aiming = false;
        client._syncCockpitWeapon();
        client.camera.updateMatrixWorld(true);
        const exported = graphOf(client.cockpit);
        const named = node => node ? exported.ids.get(node) : -1;
        profile.nodes = { gun: named(client.gunGroup), ground: named(client._gunG), air: named(client._gunA), flash: named(client.flash),
          cockGround: named(client.cockGround), cockAir: named(client.cockAir) };
        profile.emissions = Object.fromEntries(Object.entries(emissionNodes).map(([form, slots]) =>
          [form, Object.fromEntries(Object.entries(slots).map(([slot, nodes]) => [slot, nodes.map(named)]))]));
        const bindings = [];
        client.gunGroup.traverse(node => {
          for (const pair of node.userData.weaponPresentation || []) bindings.push({
            target: named(pair.target), source: pair.name, rotate: !!pair.rotate, translate: !!pair.translate });
        });
        profile.bindings = bindings;
        // Authority needs only the transform paths to ports and mirrored nodes, never FPV meshes.
        const poseIds = new Set();
        for (const id of [...bindings.map(pair => pair.target),
          ...Object.values(profile.emissions).flatMap(slots => Object.values(slots).flat())]) {
          let node = id;
          while (node >= 0 && node !== profile.nodes.gun) {
            poseIds.add(node);
            node = exported.data.nodes[node].parent;
          }
        }
        profile.poseGraph = exported.data.nodes.filter(node => poseIds.has(node.id))
          .map(({id,parent,name,matrix}) => ({id,parent,name,matrix}));
        profile.poseGunName = exported.data.nodes[profile.nodes.gun].name;
        const owners = self.userData.morph ? {ground:self.userData.morph.ground,air:self.userData.morph.air} : {ground:self.userData.rig};
        const sourceNames = new Set(bindings.map(pair => pair.source));
        profile.motion = {};
        for (const [form, owner] of Object.entries(owners)) {
          const nodes = Object.fromEntries([...sourceNames].map(name => {
            const node = owner.combat.nodes.get(name);
            if (!node) throw new Error(`Missing source cockpit mirror: ${character}/${form}/${name}`);
            return [name,{position:node.position.toArray(),rotation:[node.rotation.x,node.rotation.y,node.rotation.z],
              order:node.rotation.order,scale:node.scale.toArray(),parent:node.parent?.name || ''}];
          }));
          const sequences = Object.fromEntries(Object.entries(owner.weaponSequences).map(([slot, sequence]) => [slot,
            sequence.entries.map(entry => ({payload:entry.payload?.name || '',side:entry.side}))]));
          const tracks = (owner.referenceMotion?.fire || []).filter(track => sourceNames.has(track.node.name)).map(track => ({
            node:track.node.name,channel:track.channel,axis:track.axis,rest:track.rest,amplitude:track.amplitude,
            emitters:track.emitters.map(({slot,entry}) => ({slot,index:owner.weaponSequences[slot].entries.indexOf(entry)}))}));
          if (tracks.some(track => !track.emitters.length)) throw new Error(`Unimplemented non-emitter cockpit recoil: ${character}/${form}`);
          const hair = owner.hairFlick;
          profile.motion[form] = {nodes,sequences,tracks,
            clips:Object.fromEntries(['light','heavy'].map(slot => [slot,{duration:owner.combat.clips[slot].duration,
              lead:owner.fireLead?.[slot] || 0,tracks:owner.combat.clips[slot].tracks
                .filter(track => sourceNames.has(track.node) && !owner.combat.transported?.includes(track.node))
                .map(({node,channel,axis,keys}) => ({node,channel,axis,keys}))}])),
            durations:Object.fromEntries(['light','heavy'].map(slot => [slot,owner.combat?.clips[slot]?.duration || .55])),
            hair:hair ? {index:hair.index.name,middle:hair.middle.name,thumb:hair.thumb.name,tuft:hair.tuft.name,
              burstGap:hair.burstGap,pluckDuration:hair.pluckDuration} : null, archery:!!owner.archery};
        }
        for (const aiming of [false, true]) for (const fov of [68, 67.91, 67.9, 67.89, 35]) for (const flight of [false, true]) {
          client.aiming = aiming; client.flight = flight; client.camera.fov = fov;
          client._syncCockpitWeapon();
          cockpitVisibility.push({ character, aiming, fov, flight,
            nodes: exported.data.nodes.map(spec => ({ id: spec.id, visible: [...exported.ids.keys()][spec.id].visible })) });
        }
        for (const slot of ['light', 'heavy']) for (let level = 1; level <= 4; level++) {
          const def = d.heroWeapon(character, slot, level);
          for (const progress of [-.1, 0, .25, .5, .75, 1, 1.1]) {
            for (const [suppression, kick] of [[0, 0], [.7, 1], [-.7, .5]]) {
              const offset = client._reloadAnimOffset(def, progress);
              client._lobFc = { on: suppression !== 0, sup: suppression };
              client.weaponKick = kick;
              const matrix = pose.call(client, offset, new THREE.Vector3());
              cockpitPoses.push({ character, slot, level, progress, suppression, kick,
                offset: [offset.rx, offset.dy, offset.dz], matrix });
            }
          }
        }
        cockpits[character] = profile;
        cockpitGraphs[character] = exported.data;
        for (const form of Object.keys(owners)) {
          const body = makeUnit(`hero:${hero.kind}`, side, {ch:character,ring:false}).group;
          if (body.userData.morph) {
            const morph = body.userData.morph;
            morph.m = form === 'air' ? 1 : 0; morph.air0 = form === 'air'; morph.act = false;
            body.userData.rig = form === 'air' ? morph.air : morph.ground;
          }
          const ent = {id:1,pid:1,isSelf:true,hero:true,kind:hero.kind,mesh:body,heroY:form === 'air' ? 10 : 0,dead:false};
          const caches = cachePoints.map(point => new THREE.Vector3().fromArray(point));
          client._muzzles = Object.fromEntries(Object.entries(cacheSets).map(([key,slots]) => [key === 'air' ? 'A' : 'G',
            Object.fromEntries(Object.entries(slots).map(([slot,index]) => [slot,caches[index]]))]));
          client._muzzle = caches[muzzleCache.current]; client.flash.position.copy(client._muzzle);
          client.ents = new Map([[1,ent]]); client.flight = form === 'air'; client.aiming = false; client.camera.fov = 68;
          let serial = 0, now = 10;
          const frames = [];
          const longest = Math.max(...Object.values(body.userData.rig.weaponSequences).map(sequence => sequence.entries.length));
          for (let i = 0; i < longest * 4 + 24; i++) {
            const dt = [1/60,1/30,.1][i % 3]; now += dt;
            const shots = i < longest * 4 ? (i === 1 ? ['light','light'] : [i % 2 ? 'heavy' : 'light']) : [];
            for (const slot of shots) {
              client._markFire(1,slot,now,null,true); serial++;
              for (const owner of body.userData.morph ? [body.userData.morph.ground,body.userData.morph.air] : [body.userData.rig])
                fireReferenceWeapon(owner,ent.fireFx); // Same immutable event must never advance twice.
            }
            stepCombatFx(ent,now,dt); stepLocomotion(ent,dt,now,0,0,0);
            client.aiming = ent.fireFx?.slot === 'heavy';
            client._syncCockpitWeapon(); client.camera.updateMatrixWorld(true);
            frames.push({dt,now,shots,serial,indices:Object.fromEntries(Object.entries(body.userData.rig.weaponSequences).map(([slot,sequence]) => [slot,sequence.index])),
              slot:ent.fireFx?.slot || 'light',flashPosition:client.flash.position.toArray(),
              mirrors:bindings.map(pair => {const node=[...exported.ids.keys()][pair.target];return {target:pair.target,
                position:node.position.toArray(),quaternion:node.quaternion.toArray(),scale:node.scale.toArray()};})});
          }
          weaponPresentation.push({character,form,frames});
          disposeTree(body);
        }
        for (const {form,burst} of [...Object.keys(owners), ...(hero.kind === 'morph' ? ['switch'] : [])]
          .flatMap(form => [{form,burst:false},{form,burst:true}])) {
          const body = makeUnit(`hero:${hero.kind}`, side, {ch:character,ring:false}).group;
          if (body.userData.morph) {
            const morph = body.userData.morph;
            morph.m = form === 'air' ? 1 : 0; morph.air0 = form === 'air'; morph.act = false;
            body.userData.rig = form === 'air' ? morph.air : morph.ground;
          }
          const ent = {id:1,pid:1,isSelf:true,hero:true,kind:hero.kind,mesh:body,heroY:form === 'air' ? 10 : 0,dead:false};
          const caches = cachePoints.map(point => new THREE.Vector3().fromArray(point));
          client._muzzles = Object.fromEntries(Object.entries(cacheSets).map(([key,slots]) => [key === 'air' ? 'A' : 'G',
            Object.fromEntries(Object.entries(slots).map(([slot,index]) => [slot,caches[index]]))]));
          client._muzzle = caches[muzzleCache.current]; client.weaponKick = 0;
          client.ents = new Map([[1,ent]]); client.flight = form === 'air'; client.aiming = false; client.camera.fov = 68;
          stepCombatFx(ent,0,0); stepLocomotion(ent,0,0,0,0,0);
          client._syncCockpitWeapon();
          client._lobFc = {on:false,sup:0}; pose.call(client,{rx:0,dy:0,dz:0},new THREE.Vector3());
          let now = 0, serial = 0, acceptedSerial = 0;
          const sourceNow = performance.now.bind(performance);
          Object.defineProperty(performance,'now',{configurable:true,value:()=>now*1000});
          client.youId = 1; client._burstQ = []; client.dead = false; client.trauma = 0; client.recoil = {p:0,y:0}; client.vel = new THREE.Vector3();
          // Isolate the original echo's emission/bookkeeping; target and view recoil have separate migration fixtures.
          client._aimTarget=()=>null; client._altRangeTo=()=>1;
          client._resolveAim=range=>({point:client.camera.position.clone().addScaledVector(client.camera.getWorldDirection(new THREE.Vector3()),range)});
          client._tracer=()=>{}; client._muzzleBurst=()=>{}; client._spawnVisShell=()=>{};
          const frames = [], longest = Math.max(...Object.values(body.userData.rig.weaponSequences).map(sequence => sequence.entries.length));
          for (let i = 0; i < longest * 4 + 24; i++) {
            const dt = [1/60,1/30,.1][i % 3]; now += dt;
            const slot = i % 2 ? 'heavy' : 'light', level = i % 4 + 1;
            const flying = form === 'switch' ? i % 3 !== 0 : form === 'air';
            client.flight = flying;
            if (body.userData.morph) {
              const morph = body.userData.morph;
              morph.m = flying ? 1 : 0; morph.air0 = flying; morph.act = false;
              body.userData.rig = flying ? morph.air : morph.ground;
              ent.heroY = flying ? 10 : 0;
            }
            client.aiming = slot === 'heavy';
            client.camera.position.set(12+i*.3,80+i*.2,-9+i*.1);
            client.camera.rotation.set([-.4,0,.6][i%3],[0,.7,-1.2][i%3],0,'YXZ');
            client.camera.updateMatrixWorld(true);
            const shots = i < longest * 4 ? (i === 1 ? ['light','light'] : [slot]) : [];
            const launches = [];
            for (const fired of shots) {
              const point = client._selfMuzzle(null,100,fired);
              launches.push({slot:fired,point:point.toArray()});
              client._markFire(1,fired,now,null,true); serial++; client.weaponKick = 1;
              acceptedSerial++;
              if (burst) {
                const captured = d.heroWeapon(character,fired,level);
                client._queueBurst(captured,()=>{client._burstEchoSelf(captured,fired,{kick:0,climb:0,back:0});serial++;});
              }
            }
            if (burst) client._tickBurstFx(now);
            stepCombatFx(ent,now,dt); stepLocomotion(ent,dt,now,0,0,0);
            client._syncCockpitWeapon();
            client.weaponKick = Math.max(0,client.weaponKick-dt*kickDecay);
            const def = d.heroWeapon(character,slot,level), progress = [-.1,0,.25,.5,.75,1,1.1][i%7];
            const reloading = i % 5 === 0, suppression = slot === 'heavy' ? [0,.7,-.7][i%3] : 0;
            const reloadEnd = reloading ? now+(1-progress)*def.reload : null;
            const actualProgress = reloading ? 1-Math.max(0,reloadEnd-now)/Math.max(.001,def.reload) : 0;
            const offset = reloading ? client._reloadAnimOffset(def,actualProgress) : {rx:0,dy:0,dz:0};
            client._lobFc = {on:suppression!==0,sup:suppression};
            const matrix = pose.call(client,offset,new THREE.Vector3()); client.camera.updateMatrixWorld(true);
            const current = client.gunGroup.localToWorld(client._muzzle.clone());
            frames.push({dt,now,slot,level,flying,shots,launches,serial,acceptedSerial,reloadEnd,suppression,kick:client.weaponKick,matrix,
              pending:client._burstQ.length,indices:Object.fromEntries(Object.entries(body.userData.rig.weaponSequences).map(([slot,sequence])=>[slot,sequence.index])),
              camera:client.camera.matrixWorld.toArray(),current:current.toArray(),cache:client._muzzle.toArray()});
          }
          Object.defineProperty(performance,'now',{configurable:true,value:sourceNow});
          (burst ? burstWeaponPoses : authorityWeaponPoses).push({character,form,frames});
          for (const key of ['_aimTarget','_altRangeTo','_resolveAim','_tracer','_muzzleBurst','_spawnVisShell']) delete client[key];
          disposeTree(body);
        }
        for (const form of Object.keys(owners)) {
          const body = makeUnit(`hero:${hero.kind}`, side, {ch:character,ring:false}).group;
          if (body.userData.morph) {
            const morph = body.userData.morph;
            morph.m = form === 'air' ? 1 : 0; morph.air0 = form === 'air'; morph.act = false;
            body.userData.rig = form === 'air' ? morph.air : morph.ground;
          }
          for (const slot of ['light','heavy']) for (let level=1;level<=4;level++) for (let scenario=0;scenario<3;scenario++) {
            const def = d.heroWeapon(character,slot,level), ground = [0,50,100][scenario];
            const ent = {id:1,pid:1,isSelf:true,hero:true,kind:hero.kind,mesh:body,heroY:0,dead:false};
            const caches = cachePoints.map(point => new THREE.Vector3().fromArray(point));
            const packets=[], visual=[];
            const wall = scenario === 1 ? -24 : null;
            const cut = (a,b) => {
              const hits=[];
              if (a.y>ground && b.y<=ground) hits.push((a.y-ground)/(a.y-b.y));
              if (wall!==null && (a.z-wall)*(b.z-wall)<=0 && a.z!==b.z) hits.push((a.z-wall)/(a.z-b.z));
              return hits.length ? Math.min(...hits.filter(t=>t>=0 && t<=1))*a.distanceTo(b) : null;
            };
            const view = cameraProfiles[character][form];
            const altitude = hero.kind === 'drone' || form === 'air' ? d.FLIGHT.HOVER_M : .1;
            Object.assign(client, {side,ch:character,youId:1,heroKind:hero.kind,isDrone:hero.kind==='drone',isMorph:hero.kind==='morph',
              ents:new Map([[1,ent]]),flight:form==='air',dead:false,shopOpen:false,firing:true,aiming:slot==='heavy',mp:1e9,
              pos:new THREE.Vector3(0,ground+altitude,0),vel:new THREE.Vector3(),recoil:{p:0,y:0},trauma:0,_altAG:altitude,charge:0,
              lastFireAt:{},_settleUntil:{},_burstN:{},_steadyAt:1,_railAt:1,weaponKick:0,bullets:[],_lobCache:null,_lobFc:null,
              hud:{feed(){}},audio:null,env:null,net:{send(packet){packets.push(packet);}},
              wdef:{light:d.heroWeapon(character,'light',level),heavy:d.heroWeapon(character,'heavy',level)},
              _curWeapon:()=>({id:slot,def,st:{ammo:def.mag,reloadEnd:0}}),_aimTarget:()=>null,_moveInput:()=>false,
              _fallbackFromEmptyHeavy(){},_startReload(){},_setRailCharge(){},_queueBurst(){},
              _takeProjectile:()=>new THREE.Object3D(),_recPool:{acquire:()=>({pos:new THREE.Vector3(),vel:new THREE.Vector3(),origin:new THREE.Vector3(),guidePt:new THREE.Vector3()})},
              _fanBlast:(from,dir)=>visual.push({from:from.toArray(),direction:dir.toArray()}),
              _tracer:(from,to)=>visual.push({from:from.toArray(),to:to.toArray()}),
              _lanceVisual:(from,to)=>visual.push({from:from.toArray(),to:to.toArray()}),
              _muzzleBurst(){},_lanceFeedback(){},_lancePierced:()=>[],_rayCandidates:()=>[],raycaster:new THREE.Raycaster(),
              terrain:{heightAt:()=>ground},_surf:()=>ground,_aaAim:false,_aaEnt:null,
              _obstHitT:(x,y,z,ex,ey,ez)=>wall===null?null:cut(new THREE.Vector3(x,y,z),new THREE.Vector3(ex,ey,ez)),
              _layerHitT:(x,y,z,ex,ey,ez)=>cut(new THREE.Vector3(x,y,z),new THREE.Vector3(ex,ey,ez)),
              _blockersNear:()=>[],_blockerHitT:(x,y,z,ex,ey,ez)=>wall===null?null:cut(new THREE.Vector3(x,y,z),new THREE.Vector3(ex,ey,ez)),
              _onDeck:false,_surfHere:ground,
              _terrainHitT:(ro,rd,far)=>rd.y<0 && ro.y>ground && (ro.y-ground)/-rd.y<=far?(ro.y-ground)/-rd.y:null,
            });
            for (const owner of body.userData.morph?[body.userData.morph.ground,body.userData.morph.air]:[body.userData.rig])
              for (const sequence of Object.values(owner.weaponSequences)) sequence.index=-1;
            client._muzzles=Object.fromEntries(Object.entries(cacheSets).map(([key,slots])=>[key==='air'?'A':'G',Object.fromEntries(Object.entries(slots).map(([key,i])=>[key,caches[i]]))]));
            client._muzzle=caches[muzzleCache.current];
            const yaw = [0,.7,-1.2][scenario];
            client.camera.position.copy(client.pos).add(new THREE.Vector3(-Math.sin(yaw)*view.forward,client._eyeH(),-Math.cos(yaw)*view.forward));
            client._cameraDeClip();
            client.camera.rotation.set([0,-.2,.4][scenario],[0,.7,-1.2][scenario],0,'YXZ');
            client._syncCockpitWeapon();
            client.weaponKick=[0,.65,0][scenario];
            client._lobFc={on:scenario===2,sup:scenario===2?.7:0};
            const offset=scenario===1?client._reloadAnimOffset(def,.5):{rx:0,dy:0,dz:0};
            const gunMatrix=pose.call(client,offset,new THREE.Vector3()); client.camera.updateMatrixWorld(true);
            const advisory=client.gunGroup.localToWorld(client._muzzle.clone());
            client._lobFc=null;
            if (d.trajClass(def)==='lob') client._lobAim();
            const reticle=client._resolveAim(def.range,d.aoeClass(def)==='line').point;
            const spread=client._armSpread;
            client._armSpread=function(dir,s) {const random=Math.random;let i=0;Math.random=()=>[.37,.8][i++];try{return spread.call(this,dir,s);}finally{Math.random=random;}};
            client._tryFire(120);
            client._armSpread=spread;
            if (packets.length===0 && client.bullets.length===0) throw new Error(`Source muzzle launch rejected: ${character}/${form}/${slot}/${level}`);
            const bullet=client.bullets[0];
            const flow={character,form,slot,level,scenario,ground,wall,body:client.pos.toArray(),camera:client.camera.matrixWorld.toArray(),gun:gunMatrix,
              advisory:advisory.toArray(),reticle:reticle.toArray(),packets,visual};
            if (bullet) flow.bullet={origin:bullet.origin.toArray(),position:bullet.pos.toArray(),velocity:bullet.vel.toArray(),range:bullet.max,
              relativeMuzzle:bullet.oy,guidePoint:bullet.guidePt.toArray(),guide:bullet.guide,launchDistance:bullet.launchDist};
            if (client._lobFc?.on) flow.control={velocity:client._lobFc.vel.toArray(),range:client._lobFc.max,aim:client._lobFc.aim.toArray(),ok:client._lobFc.ok,close:client._lobFc.close};
            muzzleLaunches.push(flow);
            for (const bullet of client.bullets) client.scene.remove(bullet.mesh);
          }
          disposeTree(body);
        }
        disposeTree(self);
        disposeTree(client.cockpit);
      }
      for (const kind of ['soldier', 'rocketeer', 'howitzer', 'apc', 'tank', 'heli', 'tower', 'base']) {
        geometry.units[kind] = {};
        for (const side of ['STEEL', 'SWARM']) {
          const key = kind === 'base' ? `base:${side}` : kind === 'tower' ? kind : `creep:${kind}`;
          geometry.units[kind][side] = capture('', kind, side, key);
        }
      }
      return { geometry, cockpits, cockpitGraphs, projectileGraphs, projectileVisual: {profiles:projectileProfiles,colors:shotColors,beamColors}, cockpitRules: { ...COCKPIT, kickDecay, flash:flashRules },
        fixtures: { modelCentres, cockpitMuzzles, cockpitPoses, cockpitVisibility, cockpitElevation, weaponPresentation, cockpitFlash, authorityWeaponPoses, burstWeaponPoses, muzzleLaunches, projectileGeometry, projectileFx }, glowPng: glowTexture().image.toDataURL('image/png').split(',')[1] };
    }, { dimensionBody, aimBody: method('_entAimPoint'), poseBody, kickDecay: Number(kickDecay[1]), elevationBody, flashBody, flashRules, cameraProfiles, beamColors });
    return { ...result, inputs: [...sourceInputs].sort() };
  } finally {
    await browser.close();
  }
}
