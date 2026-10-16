// This function runs inside the offline source browser, with original builders and methods.
export function captureBodyReferences({ THREE, d, makeUnit, graphOf, fireReferenceWeapon, poseWeaponPayloads, stepUnitSpinners,
  fireUnitMotion, stepUnitMotion, stepCombatFx, morphMethods, morphHelpers, gaitMethods, castRules, captureAnatomy, anatomyHelpers,
  captureFrames, captureNpc, captureClone, captureCarrier, NPC_MODEL_KINDS, SUMMON_BUILDERS, measure, unitShotStyle, unitMotion, combatAsset, stepLocomotion, BattleClient, castRemote, cameraProfiles, disposeTree }) {
  const graphs = {}, profiles = {}, geometry = [], weapons = [], morphs = [], bipeds = [], aerials = [], quads = [], vehicles = [], combat = [], aiming = [], anatomy = [], reference = [], locomotion = [];
  const combatKeys=new Map(), presentationEvents=[], authorityBodies=[], npcBodies=[], cloneBodies=[], shieldHits=[];
  const snapshot = (graph, previous, euler = false) => [...graph.ids].flatMap(([node, id]) => {
    const row = { id, parent: graph.ids.get(node.parent) ?? -1, position: node.position.toArray(),
      quaternion: node.quaternion.toArray(), scale: node.scale.toArray(), visible: node.visible };
    if (euler) row.rotation = [node.rotation.x, node.rotation.y, node.rotation.z];
    if (node.isInstancedMesh) row.instances = graph.instancesOf(node);
    const value = JSON.stringify(row), same = previous.get(id) === value; previous.set(id, value);
    return same ? [] : [row];
  });
  const morphScalars = [-.1, 0, .005, .01, .010001, .2, .499999, .5, .500001, .8, .989999, .99, .995, 1, 1.1].map(progress => ({ progress,
    ease: morphHelpers.morphEase(progress), rest: morphHelpers.restK(progress), ground: morphHelpers.fadeA(progress, false),
    air: morphHelpers.fadeA(progress, true), active: morphHelpers.morphing(progress), shrink: morphHelpers.shrinkS(progress) }));
  const morphQuaternions = [];
  for (const angle of [0, .001, .02, .07, .8, Math.PI]) for (const sign of [-1, 1]) for (const weight of [0, .1, .5, 1]) {
    const first = [0, 0, 0, 1], second = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), angle).toArray().map(value => value * sign);
    const result = [0, 0, 0, 1]; morphHelpers.slerpQ(first, second, weight, result);
    morphQuaternions.push({first, second, weight, result});
  }
  const roster = [...Object.entries(d.CHARACTERS), ...NPC_MODEL_KINDS.filter(key=>key.startsWith('creep:')).map(modelKey =>
    ['npc_' + modelKey.replaceAll(':','_'), {side:'MERC',modelKey}]),
    ...['tower','base'].map(kind=>['npc_'+kind,{side:'MERC',modelKey:kind,sides:['STEEL','SWARM']}]),
    ...['GUER','MILI'].flatMap(side=>[...new Set(['bunker',...d.THIRD.COMP[side]])].map(kind=>{
      const modelKey=kind==='bunker'?'bunker':'creep:'+kind;
      return ['npc_'+modelKey.replaceAll(':','_'),{side,modelKey,kind,sides:[side]}];
    })),
    ...Object.keys(SUMMON_BUILDERS).map(modelKey=>['npc_'+modelKey.replaceAll(':','_'),{side:'MERC',modelKey,kind:modelKey.slice(7)}]),
    ['npc_summon_decoy_beacon',{side:'MERC',modelKey:'summon:drone_wingman',kind:'decoy_beacon'}],
    ...['decoy','hyper'].map(kind=>[kind,{side:'MERC',modelKey:kind,kind,carrier:true,ring:false}]),
    ...Object.keys(d.CHARACTERS).map(character=>[character+'_kami',{side:'MERC',modelKey:'hero:drone',kind:'kami',
      character,carrier:true,ring:false,scale:d.SQUAD.KAMI.SIZE_F}])];
  for (const [character, hero] of roster) {
    const sides = hero.sides||[...new Set([...(hero.side === 'MERC' ? ['STEEL', 'SWARM'] : [hero.side]), d.SUPER_SIDE])];
    for (const side of sides) {
      const key = side.toLowerCase() + '_' + character;
      const modelKey=hero.modelKey==='base'?'base:'+side:hero.modelKey;
      const kind=hero.kind||(hero.modelKey.startsWith('creep:')?hero.modelKey.slice(6):hero.modelKey);
      const create = () => {
        const group=makeUnit(modelKey||'hero:'+hero.kind,side,{ch:hero.character||(hero.modelKey?null:character),ring:hero.ring??true,dissolve:true}).group;
        if(hero.scale!=null)group.scale.setScalar(hero.scale);
        if(kind==='hyper')group.rotation.order='YXZ';
        if(kind==='base') {
          group.userData.bodyDimensions=measure(THREE,group,modelKey,{k:kind,s:side},false,new Map());
          const entity={mesh:group},scene=new THREE.Group();
          BattleClient.prototype._addBaseGuns.call({scene,cfg:{},center:[0,0]},entity,{x:0,z:0,s:side});
          group.add(entity.guns);
          group.userData.baseGuns=entity.guns;
        }
        return group;
      };
      const body = create();
      body.updateMatrixWorld(true);
      const measured=body.userData.bodyDimensions||measure(THREE,body,modelKey||'hero:'+hero.kind,{k:kind,s:side,ch:hero.modelKey?null:character},false,new Map());
      const dimensions={height:measured.dimH,top:measured.dimTop,radius:measured.dimR,centre:measured.dimTop-measured.dimH/2};
      const graph = graphOf(body);
      const objects = [], objectIds = new Map(), scratch = [], scratchIds = new Map(), allowedScratch = new Set();
      const encode = (value, path) => {
        if (value == null || typeof value === 'string' || typeof value === 'boolean') return value;
        if (typeof value === 'number') return Number.isFinite(value) ? value : { $number: String(value) };
        if (value.isObject3D) {
          if (graph.ids.has(value)) return { $node: graph.ids.get(value) };
          if (!allowedScratch.has(value) || value.parent || value.children.length || value.type !== 'Object3D')
            throw new Error('Body rig references an unsupported external node: ' + key + '/' + path);
          if (!scratchIds.has(value)) {
            scratchIds.set(value, scratch.length);
            scratch.push({p:value.position.toArray(),q:value.quaternion.toArray(),s:value.scale.toArray(),
              r:[value.rotation.x,value.rotation.y,value.rotation.z],order:value.rotation.order});
          }
          return { $scratch: scratchIds.get(value) };
        }
        if (value.isMaterial) {
          return { $material: graph.materialOf(value) };
        }
        for (const [flag, tag] of [['isVector2', '$vector2'], ['isVector3', '$vector3'], ['isQuaternion', '$quaternion'],
          ['isEuler', '$euler'], ['isMatrix4', '$matrix4'], ['isColor', '$color']]) {
          if (value[flag]) return { [tag]: value.toArray() };
        }
        if (typeof value !== 'object') throw new Error('Unsupported body rig value: ' + key + '/' + path);
        if (objectIds.has(value)) return { $ref: objectIds.get(value) };
        const type = Array.isArray(value) ? 'array' : value instanceof Map ? 'map' : value instanceof Set ? 'set' : 'record';
        if (type === 'record' && Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null)
          throw new Error('Unsupported body rig object: ' + key + '/' + path + '/' + value.constructor?.name);
        const id = objects.length; objectIds.set(value, id); objects.push({ type, value: null });
        if (type === 'array') objects[id].value = value.map((item, index) => encode(item, path + '/' + index));
        else if (type === 'map') objects[id].value = [...value].map(([name, item]) => [encode(name, path + '/key'), encode(item, path + '/value')]);
        else if (type === 'set') objects[id].value = [...value].map(item => encode(item, path + '/set'));
        else objects[id].value = Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined).map(([name, item]) => [name, encode(item, path + '/' + name)]));
        return { $ref: id };
      };
      const morph = body.userData.morph;
      const owners = morph ? { ground: morph.ground, air: morph.air } : body.userData.rig ? { ground: body.userData.rig } : {};
      for(const owner of Object.values(owners))for(const clip of Object.values(owner.combat?.clips||{}))for(const track of clip.tracks) {
        const signature=JSON.stringify(track.keys);
        if(combatKeys.has(signature))continue;
        const times=[...new Set([-.1,0,1,1.1,...track.keys.flatMap(([time],index)=>
          [time-.000001,time,time+.000001,...(index?[(track.keys[index-1][0]+time)/2]:[])])])];
        combatKeys.set(signature,{keys:track.keys,steps:times.map(time=>({time,value:combatAsset.sampleCombatKeys(track.keys,time)}))});
      }
      for (const owner of Object.values(owners)) for (const track of owner.tracks || []) allowedScratch.add(track.pose);
      profiles[key] = { character:hero.character||(hero.modelKey ? null : character), modelKey:modelKey||null, kind, dimensions, carrier:!!hero.carrier, static:['tower','base','bunker'].includes(kind), side, objects, scratch, forms: encode(owners, 'forms'),
        mounts:encode({turret:body.userData.turret||null,pitch:body.userData.turret?.userData.pitch||null,
          gunTilt:body.userData.gunTilt||null,muzzles:body.userData.turretMuzzles||[],muzzle:body.userData.muzzle||null,
          guns:body.userData.baseGuns||null,gunPivots:body.userData.baseGuns?.userData.pivots||[],
          gunPitches:(body.userData.baseGuns?.userData.pivots||[]).map(pivot=>pivot.userData.pitch),
          gunMuzzles:body.userData.baseGuns?.userData.muzzles||[]},'mounts'),
        npcShotSlot:['gun','beam'].includes(unitShotStyle(kind).mode)?'light':'heavy',
        shieldMaterials: Object.fromEntries(Object.entries(owners).filter(([,owner])=>owner.shield?.combat)
          .map(([form,owner])=>[form,graph.materialOf(owner.shield.barrier.userData.mat)])),
        hitShieldMaterial:body.userData.rig?.combat?.guard?.userData.mat?graph.materialOf(body.userData.rig.combat.guard.userData.mat):null,
        spin: (body.userData.spin || []).map(node => ({ node: graph.ids.get(node), axis: node.userData.spinAxis || 'y', rate: node.userData.spinRate ?? 40 })),
        morph: morph ? { gg: graph.ids.get(morph.gg), ag: graph.ids.get(morph.ag), m: morph.m, air0: morph.air0, k: morph.k, act: morph.act,
          plan: encode(morph.plan, 'morph/plan') } : null };
      graphs[key] = graph.data;
      geometry.push({ key, nodes: graph.data.nodes, materials: graph.data.materials });
      const guard=body.userData.rig?.combat?.guard;
      if(guard?.userData.hit) {
        const uniform=guard.userData.mat.uniforms.uFlash,initial=uniform.value,steps=[];
        for(const strength of [0,.1,1.8,.5,2.5,1]) {
          guard.userData.hit(strength);steps.push({strength,flash:uniform.value});
        }
        shieldHits.push({key,material:profiles[key].hitShieldMaterial,initial,steps});uniform.value=initial;
      }
      if(!Object.keys(owners).length){disposeTree(body);continue;}
      if(hero.modelKey&&!hero.carrier)npcBodies.push(captureNpc({key,kind,dimensions,create,graphOf,snapshot,
        BattleClient,fireUnitMotion,unitShotStyle,disposeTree}));
      if(!hero.modelKey)cloneBodies.push(captureClone({key,kind,dimensions,create,graphOf,snapshot,
        BattleClient,fireUnitMotion,unitShotStyle,stepCombatFx,disposeTree,d}));
      const frames=captureFrames({key,create,graphOf,snapshot,unitMotion,combatAsset,stepLocomotion,stepCombatFx,BattleClient,castRemote,
        cameraProfile:hero.modelKey?null:cameraProfiles[character],entityState:hero.carrier?{hero:false,flies:true,sp:0}:null,disposeTree,d});
      if(frames.reference)reference.push(frames.reference);
      if(frames.locomotion)locomotion.push(frames.locomotion);
      if(frames.events)presentationEvents.push(frames.events);
      if(frames.authority)authorityBodies.push(frames.authority);
      for(const [form,owner]of Object.entries(owners))if(owner.anatomical)
        anatomy.push(captureAnatomy({key,create,form,graphOf,snapshot,anatomyHelpers,gaitMethods,disposeTree}));
      for(const [form,original]of Object.entries(owners)) {
        if(!original.stab?.length&&!original.aimForward?.length)continue;
        const model=create(),owner=model.userData.morph?.[form]??model.userData.rig,rendered=graphOf(model),before=new Map();snapshot(rendered,before,true);
        const steps=[];
        for(const input of [{weight:0,slot:'light'},{weight:.0001,slot:'light',root:[.13,.7,-.2]},
          {weight:.000100001,slot:'light',disturb:true},{weight:.4,slot:'light'},{weight:1,slot:'heavy'},
          {weight:2,slot:'missing',scale:[-1,1.5,.7]},... [0,owner.launcher?.rotateStart??.2,.5,1].map(extension=>({weight:.7,slot:'heavy',extension}))]) {
          const updates=[];
          if(input.root){model.rotation.set(...input.root);model.position.set(12,20,-9);updates.push({id:rendered.ids.get(model),rotation:input.root,position:[12,20,-9]});}
          if(input.scale){model.scale.fromArray(input.scale);updates.push({id:rendered.ids.get(model),scale:input.scale});}
          if(input.disturb)for(const node of new Set((owner.aimForward||[]).map(track=>track.g.parent))) {
            node.rotation.x+=.1;node.rotation.y+=.15;updates.push({id:rendered.ids.get(node),rotation:[node.rotation.x,node.rotation.y,node.rotation.z]});
          }
          if(input.extension!=null&&owner.launcher){owner.launcher.lift.position.y=input.extension*owner.launcher.extension;
            updates.push({id:rendered.ids.get(owner.launcher.lift),position:owner.launcher.lift.position.toArray()});}
          const state={_fireAim:input.weight,_aimSlot:input.slot};
          gaitMethods.stabilize(owner);gaitMethods.forward(owner,state);model.updateMatrixWorld(true);
          steps.push({...input,state,updates,nodes:snapshot(rendered,before,true)});
        }
        aiming.push({key,form,steps});disposeTree(model);
      }
      {
        const model=create(),rendered=graphOf(model),before=new Map();snapshot(rendered,before,true);
        const forms=model.userData.morph?{ground:model.userData.morph.ground,air:model.userData.morph.air}:{ground:model.userData.rig};
        const entity={mesh:model},steps=[],events=[{slot:'light',t0:10.01},{slot:'light',t0:10.01},{slot:'heavy',t0:11.5},
          {slot:'heavy',t0:20},{slot:'light',t0:20.01},{t0:21}];
        const fields=['_aim','_aimH','_kickL','_kickR','_kickB','_chg','_fireAim','_aimSlot','_fireAge'];
        let form='ground';
        const inputs=[{now:10,delta:0},{now:10,delta:.016},{now:10.01,delta:-.1,shot:0},
          {now:10.01,delta:.016},{now:10.01,delta:.016,shot:0},{now:10.01,delta:.016,shot:1},
          {now:10.2,delta:.19,heavy:{phase:'charge',t0:10.2}},{now:10.725,delta:.525},{now:11.4,delta:.675},
          {now:11.5,delta:.1,shot:2,heavy:{phase:'fire',t0:11.5}},{now:11.62,delta:.12},
          {now:11.620001,delta:.000001},{now:12,delta:.379999},{now:13.1,delta:1.1},
          {now:20,delta:6.9,form:forms.air?'air':'ground',shot:3},{now:20.01,delta:.01,shot:4},
          {now:21,delta:.99,form:'ground',shot:5},{now:22.5,delta:1.5}];
        for(const age of [0,.034999,.035,.035001,.3,.549999,.55,.6])inputs.push({now:30+age,delta:age===0?.016:.001,unitFire:age===0});
        for(const unitOnly of ['nan','infinity'])inputs.push({now:31,delta:.1,unitOnly});
        for(const input of inputs) {
          if(input.form)form=input.form;
          model.userData.rig=forms[form];
          if(input.shot!=null)entity.fireFx=events[input.shot];
          if(input.heavy)entity.heavyFx={...input.heavy};
          const unitMuzzle=input.unitFire?forms[form].attacks?.[0]?.muzzles[0]:null;
          if(unitMuzzle)fireUnitMotion(forms[form],unitMuzzle,input.now);
          if(input.unitOnly)stepUnitMotion(forms[form],input.unitOnly==='nan'?NaN:Infinity);
          else stepCombatFx(entity,input.now,input.delta);
          model.updateMatrixWorld(true);
          const state=entity.cfx?Object.fromEntries(Object.entries(entity.cfx).filter(([name])=>name!=='fireEvent')):null;
          steps.push({...input,form,heavyInput:input.heavy??null,unitMuzzle:unitMuzzle?rendered.ids.get(unitMuzzle):null,state,
            event:entity.cfx?.fireEvent?events.indexOf(entity.cfx.fireEvent):-1,heavy:entity.heavyFx??null,
            forms:Object.fromEntries(Object.entries(forms).map(([name,owner])=>[name,{
              fields:Object.fromEntries(fields.filter(field=>field in owner).map(field=>[field,typeof owner[field]==='number'&&!Number.isFinite(owner[field])?String(owner[field]):owner[field]])),
              indices:Object.fromEntries(Object.entries(owner.weaponSequences||{}).map(([slot,sequence])=>[slot,sequence.index])),
              blink:(owner.blink||[]).map(blink=>blink.base??null),attacks:(owner.attacks||[]).map(attack=>Number.isFinite(attack.firedAt)?attack.firedAt:null),
              hair:owner.hairFlick?{firedAt:Number.isFinite(owner.hairFlick.firedAt)?owner.hairFlick.firedAt:null,
                startedAt:Number.isFinite(owner.hairFlick.startedAt)?owner.hairFlick.startedAt:null}:null}])),
            materials:[...rendered.materialIds].flatMap(([material,id])=>Number.isFinite(material.emissiveIntensity)?[{id,emission:material.emissiveIntensity}]:[]),
            nodes:snapshot(rendered,before,true)});
        }
        combat.push({key,events,steps});disposeTree(model);
      }
      for (const [form, original] of Object.entries(owners)) {
        if (!['biped','aerial','quad','wheeled','tracked'].includes(original.kind)) continue;
        const model = create();
        const owner = model.userData.morph?.[form] ?? model.userData.rig;
        const rendered = graphOf(model), before = new Map(); snapshot(rendered, before, true);
        const initial = {ph:1.23,amp:0,lean:0,accel:0,roll:0,pitch:0}, state = {...initial}, entity = {}, steps = [];
        const top = owner.top || (owner.kind === 'aerial' ? 20 : owner.kind === 'biped' && !owner.hop ? 8 : 10);
        const capture = input => {
          model.updateMatrixWorld(true);
          steps.push({...input,state:{...state},profile:owner.limbP ?? null,castResult:entity.castFx??null,
            tracks:(owner.tracks || []).map(track=>({travel:track.travel,pose:{p:track.pose.position.toArray(),q:track.pose.quaternion.toArray(),s:track.pose.scale.toArray(),
              r:[track.pose.rotation.x,track.pose.rotation.y,track.pose.rotation.z]}})),
            jets:(owner.jets || []).map(jet=>({opacity1:jet.m1.opacity,opacity2:jet.m2.opacity,emission:jet.m1.emissiveIntensity})),nodes:snapshot(rendered,before,true)});
        };
        let now = 0;
        for (const input of [
          {delta:0,fraction:0,acceleration:0,yawRate:0}, {delta:.016,fraction:0,acceleration:0,yawRate:.2},
          {delta:.1,fraction:.25,acceleration:15,yawRate:.5,lateralF:.1}, {delta:.3,fraction:.65,acceleration:6,yawRate:-1.8,lateralF:-.4},
          {delta:.6,fraction:.95,acceleration:0,yawRate:4,lateralF:.6}, {delta:2,fraction:1.3,acceleration:22,yawRate:-5,forwardF:-1,lateralF:-1.3},
          {delta:.016,fraction:1,acceleration:0,yawRate:0,pose:{_aim:1,_aimH:1,_fireAim:1,_aimSlot:'light',_kickL:.7,_kickR:.4,_kickB:.3,_chg:.8}},
          {delta:.1,fraction:.55,acceleration:-15,yawRate:1,pose:{_aim:1,_aimH:.4,_fireAim:.2,_aimSlot:'heavy',_kickL:.2,_kickR:1.1,_kickB:.5,_chg:-.6}},
          {delta:.2,fraction:0,acceleration:-30,yawRate:-2,pose:{_aim:0,_aimH:0,_fireAim:0,_aimSlot:'missing',_kickL:0,_kickR:0,_kickB:0,_chg:0}},
          {delta:2,fraction:0,acceleration:0,yawRate:0}, {delta:2,fraction:0,acceleration:0,yawRate:0,pose:{_aimSlot:'light'}},
          ...[null,-.1,0,.33,.330001,1,1.7,6.5,6,6,.4,.132,.131999,0,0,1.1,.2,0].map(jump=>
            ({delta:.1,fraction:.35,acceleration:0,yawRate:.2,jump})),
          ...['atk','def'].flatMap(slot=>[false,true].flatMap(dir=>[-.000001,0,.299999,.3,.45,1].map(castPhase=>
            ({delta:.016,fraction:.35,acceleration:0,yawRate:.2,cast:{slot,dir},castPhase})))),
        ]) {
          now += input.delta;
          Object.assign(owner, input.pose ?? {}); state.accel = input.acceleration;
          const speed = top * input.fraction, forward = speed * (input.forwardF ?? 1), lateral = top * (input.lateralF ?? 0);
          if (owner.kind === 'biped') gaitMethods.biped(state, owner, input.delta, now, speed, input.yawRate);
          else if (owner.kind === 'quad') gaitMethods[owner.cephalopod ? 'cephalopod' : 'quad'](state, owner, input.delta, now, speed, input.yawRate);
          else if (owner.kind === 'aerial') gaitMethods.aerial(state, owner, input.delta, now, forward, lateral, input.yawRate);
          else gaitMethods.vehicle(state, owner, input.delta, now, speed, forward, input.yawRate);
          gaitMethods.held(owner);
          const castInput=input.cast?{...input.cast,t0:now-input.castPhase*(owner.combat?.clips[input.cast.slot]?.duration??
            (input.cast.slot==='atk'?castRules.duration.atk:castRules.duration.other))}:null;
          if(castInput)entity.castFx=castInput;
          gaitMethods.cast(state,owner,entity,input.delta,now);
          if(Object.hasOwn(input,'jump'))gaitMethods.jump(state,owner,{heroY:input.jump},input.delta);
          gaitMethods.species(state,owner,input.delta,now,speed);
          capture({...input,now,speed,forward,lateral,castInput});
        }
        if (['wheeled','tracked'].includes(owner.kind)) for (const [invalid,value] of [['delta','negative'],['delta','nan'],['delta','infinity'],
          ['now','nan'],['speed','infinity'],['forward','nan'],['yawRate','infinity']]) {
          const input={delta:.1,now,speed:1,forward:1,yawRate:1,lateral:0,acceleration:state.accel,travelOnly:true,invalid,value};
          const args={...input};args[invalid]=value==='negative'?-.1:value==='nan'?NaN:Infinity;
          gaitMethods.travel(owner,state,args.delta,args.now,args.speed,args.forward,args.yawRate);
          capture(input);
        }
        ({biped:bipeds,aerial:aerials,quad:quads,wheeled:vehicles,tracked:vehicles}[owner.kind]).push({key,form,kind:owner.kind,initial,
          hop:!!owner.hop,cephalopod:!!owner.cephalopod,steps}); disposeTree(model);
      }
      if (morph) {
        const model = create();
        model.updateMatrixWorld(true);
        const rendered = graphOf(model), state = model.userData.morph, before = new Map(); snapshot(rendered, before);
        const steps = [];
        for (const input of [{ set: 0, delta: 0, altitude: 0 }, { set: .01, delta: 0, altitude: 0 },
          { set: .010001, delta: 0, altitude: 0, perturb: true }, { set: .2, delta: 0, altitude: 0, perturb: true },
          { delta: -.1, altitude: d.MORPH.GROUND_Y + .001 },
          { set: .499999, delta: 0, altitude: 0 }, { set: .5, delta: 0, altitude: 0, perturb: true },
          { set: .5 - morphHelpers.MORPH_FX.FADE * .003999, delta: 0, altitude: 0 },
          { set: .5 - morphHelpers.MORPH_FX.FADE * .004001, delta: 0, altitude: 0 },
          { set: .5 + morphHelpers.MORPH_FX.FADE * .998999, delta: 0, altitude: 0 },
          { set: .5 + morphHelpers.MORPH_FX.FADE * .999001, delta: 0, altitude: 0 },
          { set: .500001, delta: 0, altitude: 0 }, { set: .8, delta: 0, altitude: 0 }, { set: .99, delta: 0, altitude: 0 },
          { set: 1, delta: 0, altitude: 0 }, { delta: .1, altitude: d.MORPH.GROUND_Y },
          { delta: .016, altitude: d.MORPH.GROUND_Y + .001, perturb: true }, { delta: 2, altitude: 0 },
          { delta: 2, altitude: 0 }, { delta: 2, altitude: d.MORPH.GROUND_Y + .001 }, { delta: 2, altitude: d.MORPH.GROUND_Y + .001 }]) {
          if ('set' in input) state.m = input.set;
          morphMethods.swap({ heroY: input.altitude }, model, input.delta);
          const disturbed = input.perturb ? [state.plan.g.rest[0]?.n, state.plan.a.rest[0]?.n].filter(Boolean) : [];
          for (const node of disturbed) {
            node.position.x += .07; node.quaternion.multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(.11, -.03, .05)));
            node.scale.x *= 1.05;
          }
          morphMethods.pose(state); model.updateMatrixWorld(true);
          steps.push({ ...input, disturbed: disturbed.map(node => rendered.ids.get(node)), nodes: snapshot(rendered, before),
            result: { m: state.m, k: state.k, air: state.air0, act: state.act, groundVisible: state.gg.visible, airVisible: state.ag.visible },
            fades: { ground: state.plan.g.fade.map(entry => entry.a), air: state.plan.a.fade.map(entry => entry.a) },
            materials: [...rendered.materialIds].map(([material, id]) => ({ id, opacity: material.opacity, transparent: material.transparent, depth: material.depthWrite })) });
        }
        morphs.push({ key, steps }); disposeTree(model);
      }
      if (!Object.values(owners).some(owner => owner.weaponSequences)) { disposeTree(body); continue; }
      const before = new Map(); snapshot(graph, before);
      body.position.set(12, 20, -9); body.rotation.y = .7 + Math.PI;
      const events = [{ slot: 'light', t0: 10 }, { slot: 'light', t0: 10 }, { slot: 'heavy', t0: 10.1 }, { slot: 'light', t0: 10.2 }];
      const steps = [];
      for (const [event, duplicate] of [[events[0], false], [events[0], true], [events[1], false], [events[2], false], [events[3], false]]) {
        for (const owner of Object.values(owners)) fireReferenceWeapon(owner, event);
        for (const owner of Object.values(owners)) poseWeaponPayloads(owner, event.t0);
        body.updateMatrixWorld(true);
        const forms = Object.fromEntries(Object.entries(owners).map(([form, owner]) => [form, {
          indices: Object.fromEntries(Object.entries(owner.weaponSequences).map(([slot, sequence]) => [slot, sequence.index])),
          emitters: (owner.referenceMotion?.fire || []).flatMap(track => (track.emitters || []).map(({slot, entry}) => ({slot,
            index: owner.weaponSequences[slot].entries.indexOf(entry), at: Number.isFinite(entry.firedAt) ? entry.firedAt : null}))),
          muzzles: Object.fromEntries(Object.entries(owner.muzzles).map(([slot, muzzle]) => [slot, { node: graph.ids.get(muzzle.n) ?? -1,
            point: muzzle.n?.getWorldPosition(new THREE.Vector3()).toArray() ?? null, fxOnly: !!muzzle.fxOnly }])) }]));
        steps.push({ ...event, duplicate, forms, nodes: snapshot(graph, before) });
      }
      for (const now of [10.3, 10.75, 11.5]) {
        for (const owner of Object.values(owners)) poseWeaponPayloads(owner, now);
        body.updateMatrixWorld(true); steps.push({ now, nodes: snapshot(graph, before) });
      }
      for (const delta of [0, .016, .1]) {
        stepUnitSpinners(body.userData.spin, delta);
        body.updateMatrixWorld(true); steps.push({ spin: delta, nodes: snapshot(graph, before) });
      }
      weapons.push({ key, position: [12, 20, -9], yaw: .7 + Math.PI, steps });
      disposeTree(body);
    }
  }
  return { graphs, profiles, fixtures: { bodyGeometry: geometry, bodyWeapons: weapons, bodyMorphs: morphs, bodyBipeds: bipeds, bodyAerials: aerials,
    bodyQuads:quads, bodyVehicles:vehicles, bodyCombat:combat, bodyAiming:aiming, bodyAnatomy:anatomy,
    bodyReferenceMotion:reference, bodyLocomotion:locomotion, bodyCombatKeys:[...combatKeys.values()],
    bodyPresentationEvents:presentationEvents, bodyAuthorityLocomotion:authorityBodies, npcBodies, cloneBodies, bodyShieldHits:shieldHits,
    carrierBodyMotion:captureCarrier({THREE,BattleClient,d}), morphScalars, morphQuaternions } };
}
