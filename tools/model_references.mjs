import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { captureBodyReferences } from './body_references.mjs';
import { captureAnatomicalReferences } from './anatomical_references.mjs';
import { captureBodyFrames } from './body_frame_references.mjs';
import { captureNpcBodyReferences, captureCloneBodyReferences } from './npc_body_references.mjs';
import { captureCarrierBodyMotion } from './carrier_body_references.mjs';
import { captureCivilianBodies } from './civilian_body_references.mjs';
import { captureBodyViewReferences } from './body_view_references.mjs';
import { captureNpcShotReferences } from './npc_shot_references.mjs';
import { captureHeroShotReferences } from './hero_shot_references.mjs';
import { captureRemoteShotReferences } from './remote_shot_references.mjs';
import { captureFanFallbackReferences } from './fan_fallback_references.mjs';
import { captureSpriteReferences } from './sprite_references.mjs';
import { captureFirstPersonShields } from './first_person_shield_references.mjs';
import { captureHurtOverlay } from './hurt_overlay_references.mjs';
import { captureBloodSplats } from './blood_splat_references.mjs';
import { captureSplatPaint, captureSplatRasters } from './splat_paint_references.mjs';
import { captureDestruction } from './destruction_references.mjs';
import { captureSceneDamage } from './scene_damage_references.mjs';
import { captureMobileDamage } from './mobile_damage_references.mjs';
import { captureDamageFx } from './damage_fx_references.mjs';
import { captureMissilePresentation } from './missile_presentation_references.mjs';
import { captureBodyRemoval } from './body_removal_references.mjs';
import { captureDissolve } from './dissolve_references.mjs';
import { captureDeathSequences } from './death_sequence_references.mjs';
import { captureDeathOverlay, captureDeathOverlayRasters } from './death_overlay_references.mjs';

// Measure the actual source model graph offline; native gameplay consumes only saved scalars.
export async function modelReferences(source, gameSource, cameraProfiles) {
  const { chromiumOrNull, chromePath } = await import(pathToFileURL(join(source, 'tools/pw.mjs')).href);
  const chromium = await chromiumOrNull();
  if (!chromium) throw new Error('Model migration requires the source development Playwright runtime');
  const text = gameSource.replace(/\r\n/g, '\n');
  const shieldSetupStart=text.indexOf('this._fpsShieldMesh = this._createFrontShieldMesh(');
  const shieldSetupEnd=text.indexOf('this.camera.add(this._fpsShieldMesh);',shieldSetupStart);
  if(shieldSetupStart<0||shieldSetupEnd<=shieldSetupStart)throw new Error('Missing original first-person shield constructor setup');
  const firstPersonShieldSetup=text.slice(shieldSetupStart,shieldSetupEnd+'this.camera.add(this._fpsShieldMesh);'.length);
  const castRemoteMatch = /const dirCast = castDirF\(ev\.fx, cpNow && Math\.hypot\(wx - cpNow\.x, wz - cpNow\.z\) > ([\d.]+)\)/.exec(text);
  if (!castRemoteMatch) throw new Error('Missing original cast animation distance gate');
  const castRemote = Number(castRemoteMatch[1]);
  const { grabFn, grabConst, grabBlock, grabMethod } = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const hurtCss=await readFile(join(source,'public/css/style.css'),'utf8');
  const mainUiSource=(await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n');
  const reflashSource=grabFn(mainUiSource,'_reflash');
  const vfxSource=(await readFile(join(source,'public/js/vfx.js'),'utf8')).replace(/\r\n?/g,'\n');
  const heroShotSource=['energyMat','combatGeometry','combatDischarge'].map(name=>grabFn(vfxSource,name)).join('\n');
  const shotDefinitions=['UNIT_SHOT_STYLE','UNIT_GUN','UNIT_TOWER','UNIT_BASE'].map(name=>grabConst(vfxSource,name)).join('\n');
  const shotCaps=/lowPower\(\) \? (\d+) : (\d+)/.exec(vfxSource.slice(vfxSource.indexOf('const crowded ='),vfxSource.indexOf('\n',vfxSource.indexOf('const crowded ='))));
  const shotMaximum=/const FX_MAX = (\d+);/.exec(text);
  if(!shotCaps||!shotMaximum)throw new Error('Missing original transient effect budgets');
  const shotLimits={low:Number(shotCaps[1]),normal:Number(shotCaps[2]),maximum:Number(shotMaximum[1]),pools:{},prewarm:{}};
  const spritePool=/const SPRITE_POOL_MAX = (\d+);/.exec(text);
  if(!spritePool)throw new Error('Missing original sprite pool budget');
  for(const [key,pool]of [['sprite_fire','_spritePoolFire'],['sprite_smoke','_spritePoolSmoke']]) {
    const prewarm=new RegExp(`this\\.${pool}\\.prewarm\\((\\d+)\\)`).exec(text);
    if(!prewarm)throw new Error('Missing original sprite prewarm: '+pool);
    shotLimits.pools[key]=Number(spritePool[1]);shotLimits.prewarm[key]=Number(prewarm[1]);
  }
  for(const [key,pool,next]of [['spark','_sparkPool','_ringPool'],['shock','_ringPool','_beamPool'],['beam6','_beamPool','_popPool'],['comic','_popPool','_numPool']]) {
    const body=vfxSource.slice(vfxSource.indexOf('const '+pool),vfxSource.indexOf('const '+next));
    const values=/max: (\d+), prewarm: (\d+)/.exec(body);
    if(!values)throw new Error('Missing original effect pool budget: '+key);
    shotLimits.pools[key]=Number(values[1]);shotLimits.prewarm[key]=Number(values[2]);
  }
  const civilianModelSource=(await readFile(join(source,'public/js/npcModels.js'),'utf8')).replace(/\r\n?/g,'\n');
  const civilianMethods=Object.fromEntries(['frustum','strut','glowPlate','markBatch','civilianSurface','addCivilianHair',
    'addCivilianClothing','addProfessionKit','buildCivilian'].map(name=>[name,grabFn(civilianModelSource,name)]));
  const serverSource = (await readFile(join(source, 'server/sim.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const npcTargetYExpression = /ty: ([^\n]+),\n/.exec(grabMethod(serverSource, '_tickBaseGuns'))?.[1];
  const npcCompanionYExpression = /ty: ([^\n]+),\n/.exec(grabMethod(serverSource, '_tickSummons'))?.[1];
  const npcShotPointDeclaration = /const to = new THREE\.Vector3\(tx,[^\n]+;/.exec(grabMethod(text, '_onEvent'))?.[0];
  if (!npcTargetYExpression || !npcCompanionYExpression || !npcShotPointDeclaration) throw new Error('Missing source NPC target-height report/presentation seam');
  const locomotionSource = (await readFile(join(source, 'public/js/locomotion.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const combatRules = Object.fromEntries(['AIM_HOLD_S','HEAVY_CHARGE_ASSUME_S','HEAVY_FIRE_HOLD_S','FX_K'].map(name => {
    const match = new RegExp(`const ${name} = ([\\d.]+);`).exec(locomotionSource);
    if (!match) throw new Error('Missing original combat presentation constant: ' + name);
    return [name, Number(match[1])];
  }));
  const castDuration = /cf\.slot === 'atk' \? ([\d.]+) : ([\d.]+)/.exec(grabFn(locomotionSource, 'stepCastPose'));
  if (!castDuration) throw new Error('Missing original cast presentation durations');
  const castRules = { defaults: new Function(grabConst(locomotionSource, 'CAST_DEF') + '\nreturn CAST_DEF;')(),
    duration: {atk:Number(castDuration[1]),other:Number(castDuration[2])} };
  const fullLocomotion = grabFn(locomotionSource, 'stepLocomotion');
  const heldStart = fullLocomotion.indexOf("  if (rig.kind === 'aerial' && rig.heldWeapons?.length");
  const heldEnd = fullLocomotion.indexOf('\n', heldStart);
  const speciesStart = fullLocomotion.indexOf("  if (rig.predatory && rig.kind === 'biped') {");
  const speciesEnd = fullLocomotion.indexOf('  stepStab(rig);', speciesStart);
  if (heldStart < 0 || heldEnd <= heldStart || speciesStart < 0 || speciesEnd <= speciesStart)
    throw new Error('Missing original held-aim/species post-pass seams');
  const morphSource = Object.fromEntries(['morphSwap', 'morphPose', 'morphSide'].map(name => [name, grabFn(locomotionSource, name)]));
  for (const name of ['damp', 'clamp']) {
    const line = new RegExp(`const ${name} = [^;]+;`).exec(locomotionSource)?.[0];
    if (!line) throw new Error('Missing original locomotion helper: ' + name);
    morphSource[name] = line;
  }
  morphSource.fold = grabConst(locomotionSource, 'FOLD');
  const gaitDefinitions = ['ACC_REF', 'accUp', 'accDn', 'idleOf', 'ease01'].map(name => {
    const line = new RegExp(`const ${name} = [^;]+;`).exec(locomotionSource)?.[0];
    if (!line) throw new Error('Missing original gait helper: ' + name);
    return line;
  });
  const signatures = ['gsig', 'fsig'].map(name => {
    const marker = 'const ' + name + ' =', start = locomotionSource.indexOf(marker);
    const brace = locomotionSource.indexOf('{', start);
    if (start < 0 || brace < start) throw new Error('Missing original movement signature: ' + name);
    return locomotionSource.slice(start, brace) + grabBlock(locomotionSource, marker) + ';';
  });
  const gaitSource = [morphSource.damp, morphSource.clamp, grabConst(locomotionSource, 'S0'), grabConst(locomotionSource, 'CAST_DEF'), ...gaitDefinitions,
    ...signatures,
    `function heldWeaponAim(rig) {${fullLocomotion.slice(heldStart,heldEnd)}}`,
    `function speciesPose(L,rig,dt,now,speed) {${fullLocomotion.slice(speciesStart,speciesEnd)}}`,
    ...['flexChain', 'gunPitch', 'stabilizeHead', 'syncLegsToHips', 'whipTail', 'poseBipedAim', 'braceBipedArms', 'stepBiped', 'stepHop',
      'poseFlightWing', 'stepAerial', 'softLeg', 'tentGuard', 'headArc', 'stepQuad', 'stepCephalopod', 'stepVehicle', 'stepJumpPose', 'castDrive', 'stepCastPose',
      'stepStab', 'stepAimForward', 'poseArchery']
      .map(name => grabFn(locomotionSource, name))].join('\n');
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
  const beamColors = {SWARM:Number(beamColorsMatch[1]),STEEL:Number(beamColorsMatch[2]),SUPER:Number(beamColorsMatch[2])};
  const method = name => {
    const begin = text.indexOf(`\n  ${name}(`), finish = text.indexOf('\n  }\n', begin);
    if (begin < 0 || finish < 0) throw new Error(`Missing source model method: ${name}`);
    return `return function ${text.slice(begin + 1, finish + 4).trimStart().slice(name.length)}`;
  };
  const browser = await chromium.launch({ headless: true, executablePath: chromePath() });
  const sourceInputs = new Set(['server/sim.js','public/js/main.js','public/css/style.css']);
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
    const result = await page.evaluate(async ({ dimensionBody, aimBody, poseBody, kickDecay, elevationBody, flashBody, flashRules, cameraProfiles, beamColors, bodyCaptureSource, anatomyCaptureSource, frameCaptureSource, npcCaptureSource, cloneCaptureSource, carrierCaptureSource, civilianCaptureSource, viewCaptureSource, shotCaptureSource, heroShotCaptureSource, heroShotSource, remoteShotCaptureSource, fanFallbackCaptureSource, spriteCaptureSource, destructionCaptureSource, deathSequenceCaptureSource, deathOverlayCaptureSource, firstPersonShieldCaptureSource, firstPersonShieldSetup, hurtCaptureSource, hurtCss, reflashSource, bloodCaptureSource, splatPaintCaptureSource, mainUiSource, shotDefinitions, shotLimits, civilianMethods, npcTargetYExpression, npcCompanionYExpression, npcShotPointDeclaration, morphSource, gaitSource, combatRules, castRules, castRemote }) => {
      const THREE = await import('three');
      const d = await import('/js/data.js');
      const { makeUnit } = await import('/js/models.js');
      const { NPC_MODEL_KINDS,CIVILIAN_PROFESSION_KITS } = await import('/js/npcModels.js');
      const { generateCivilian } = await import('/js/civilianAppearance.js');
      const { CIVILIAN_OPTIONS } = await import('/js/civilianContent.js');
      const { finishUnitSurfaces } = await import('/js/unitSurfaces.js');
      const { sceneryGeometry } = await import('/js/sceneryGeometry.js');
      const geo = await import('/js/geo3d.js');
      const { limbChain } = await import('/js/unitRig.js');
      const { SUMMON_BUILDERS } = await import('/js/summonModels.js');
      const { buildHazard, buildLoot, buildAirdrop, buildMineBump, stepFireVisual } = await import('/js/hazards.js');
      const { WEATHER_SURFACE } = await import('/js/weatherState.js');
      const toon=await import('/js/toon.js');
      const { disposeTree,outlinify } = toon;
      const { glowTexture, projectileMesh, stepProjectileFx, makeShieldMaterial, shieldHitStrength, stepShieldMaterial,
        SHIELD_FLASH_REF, SHIELD_PRESENTATION_EXPAND, unitShotStyle } = await import('/js/vfx.js');
      const fx=await import('/js/vfx.js');
      const sceneDamage=await import('/js/sceneDamage.js');
      const mapBuilding=await import('/js/mapBuilding.js');
      const {flameGeometry}=await import('/js/sceneDisasterGeometry.js');
      const {characterCombatStyle}=await import('/js/characterStyle.js');
      const {characterShieldTexture}=await import('/js/castfx.js');
      const {setLowPower}=await import('/js/mobile.js');
      const { BattleClient, COCKPIT } = await import('/js/game.js');
      const { stepCombatFx, stepLocomotion } = await import('/js/locomotion.js');
      const { fireReferenceWeapon, poseWeaponPayloads, stepUnitSpinners, stepVehicleMotion, fireUnitMotion, stepUnitMotion } = await import('/js/unitMotion.js');
      const morphHelpers = await import('/js/morphrig.js');
      const gaitHelpers = await import('/js/gaitcurve.js');
      const anatomyHelpers = await import('/js/anatomicalPose.js');
      const unitMotion = await import('/js/unitMotion.js');
      const combatAsset = await import('/js/forge/combatAsset.js');
      const {COMBAT_ASSETS}=await import('/js/forge/combatAssets.js');
      const lod = await import('/js/lod.js');
      const bodyPresentationLod = [];
      for(const lowPower of [false,true])for(const distance of [-1,0,149.999999,150,299.999999,300,599.999999,600,1200]) {
        const squared=distance<0?distance:distance*distance,stride=lod.lodStrideByD2(squared,lowPower);
        for(const id of ['1','two','unit/\ud83d\ude80','\u4e09\u6a5f'])for(const frame of [0,1,2,17,4294967295])
          bodyPresentationLod.push({distance:squared,lowPower,id,frame,stride,hash:lod.lodHash(id),due:lod.lodDue(frame,id,stride)});
      }
      const bodyCastDirection = [];
      for(const effect of [...new Set([...d.castDirF.toString().matchAll(/fx === '([^']+)'/g)].map(match=>match[1])),'missing'])
        for(const remote of [false,true])bodyCastDirection.push({effect,remote,result:d.castDirF(effect,remote)});
      const gaitScope = { ...d, ...gaitHelpers, stepVehicleMotion };
      const gaitMethods = new Function(...Object.keys(gaitScope), `const GAIT_ANAT=true; ${gaitSource}
        return {biped:stepBiped,aerial:stepAerial,quad:stepQuad,cephalopod:stepCephalopod,vehicle:stepVehicle,
          travel:stepVehicleMotion,wing:poseFlightWing,jump:stepJumpPose,cast:stepCastPose,held:heldWeaponAim,species:speciesPose,
          stabilize:stepStab,forward:stepAimForward,archery:poseArchery};`)(...Object.values(gaitScope));
      const morphScope = { ...d, ...morphHelpers };
      const morphMethods = new Function(...Object.keys(morphScope), `
        const MORPH_RIG=true; ${morphSource.damp} ${morphSource.clamp} ${morphSource.fold}
        const _mt={p:[0,0,0],q:[0,0,0,1],s:[1,1,1]}, _mq=[0,0,0,1];
        ${morphSource.morphSide} ${morphSource.morphPose} ${morphSource.morphSwap}
        return {swap:morphSwap,pose:morphPose};`)(...Object.values(morphScope));
      const shieldTemplate = makeShieldMaterial(0);
      const sourceNumber = (body, pattern, label) => {
        const match = pattern.exec(body); if (!match) throw new Error('Missing body presentation rule: ' + label);
        return Number(match[1]);
      };
      const bodyRules = { cast: castRules, combat: combatRules, payloadScale: sourceNumber(fireReferenceWeapon.toString(), /active\.payload\.scale\.setScalar\(([\d.]+)\)/, 'payload scale'),
        npcKinds:NPC_MODEL_KINDS.filter(key=>key.startsWith('creep:')).map(key=>key.slice('creep:'.length)),
        entityKeys:Object.fromEntries([...NPC_MODEL_KINDS.filter(key=>key.startsWith('creep:')).map(key=>[key.slice(6),'npc_'+key.replaceAll(':','_')]),
          ...['tower','base','bunker'].map(kind=>[kind,'npc_'+kind]),
          ...Object.keys(SUMMON_BUILDERS).map(key=>[key.slice(7),'npc_'+key.replaceAll(':','_')]),
          ['decoy_beacon','npc_summon_decoy_beacon']]),
        tpsMuzzleForward:sourceNumber(BattleClient.prototype._selfMuzzle.toString(),/addScaledVector\(fwd, ([\d.]+)\)/,'TPS absent/FX-only muzzle forward offset'),
        presentation: {castRemote,lod:lod.LOD,castDefault:d.castDirF('',false),
          flyKinds:[...BattleClient.prototype._spawnUnit.toString().match(/flies: ([^\n]+)/)[1].matchAll(/e\.k === '([^']+)'/g)].map(match=>match[1]),
          remote:{positionResponse:sourceNumber(BattleClient.prototype._updateEnts.toString(),/const k = lerpFPS\(([\d.]+), dt\)/,'remote planar interpolation'),
            headingResponse:sourceNumber(BattleClient.prototype._updateEnts.toString(),/pyaw \+ dy \* lerpFPS\(([\d.]+), dt\)/,'remote heading interpolation'),
            stoppedSquared:sourceNumber(BattleClient.prototype._updateEnts.toString(),/adx \* adx \+ adz \* adz <= ([\d.]+)/,'stationary hero firing heading'),
            laneSeed:sourceNumber(BattleClient.prototype._updateEnts.toString(),/curSeed = laneY \+ ([\d.]+)/,'lane surface standing seed')},
          laneSurface:{segment:sourceNumber(BattleClient.prototype._buildLaneSurf.toString(),/const SEG = ([\d.]+)/,'lane surface sample spacing'),
            radius:sourceNumber(BattleClient.prototype._buildLaneSurf.toString(),/R = ([\d.]+)/,'lane surface strict query radius'),
            cell:sourceNumber(BattleClient.prototype._buildLaneSurf.toString(),/CELL = ([\d.]+)/,'lane surface grid width'),
            seedStep:sourceNumber(BattleClient.prototype._buildLaneSurf.toString(),/py \+ ([\d.]+)/,'lane surface march seed')},
          carrier:{response:sourceNumber(BattleClient.prototype._updateEnts.toString(),/wantPit[^\n]*lerpFPS\(([\d.]+), dt\)/,'carrier heading/pitch response'),
            pitchThreshold:sourceNumber(BattleClient.prototype._updateEnts.toString(),/dh \+ Math\.abs\(dv\) > ([\de.-]+)/,'carrier motion threshold')},
          aimHold:sourceNumber(BattleClient.prototype._markFire.toString(),/until: t0 \+ ([\d.]+)/,'shot facing hold'),
          nearestInterval:sourceNumber(BattleClient.prototype._nearestEnemy.toString(),/now \+ ([\d.]+)/,'presentation acquisition interval'),
          vehicleRange:sourceNumber(BattleClient.prototype._aimVehicleTurret.toString(),/\* ([\d.]+), true/,'vehicle visual acquisition range'),
          baseAimHold:sourceNumber(BattleClient.prototype._onEvent.toString(),/ent\._gunAim[\s\S]*?until: t0 \+ ([\d.]+)/,'independent base gun aim hold'),
          shotHeight:sourceNumber(npcShotPointDeclaration,/ev\.ty \|\| 0\) \+ ([\d.]+)/,'NPC target presentation height'),
          fallbackHeight:sourceNumber(BattleClient.prototype._npcMuzzle.toString(),/ent\.dimH \* ([\d.]+)/,'NPC body muzzle fallback height'),
          garrisonRadius:sourceNumber(BattleClient.prototype._npcMuzzle.toString(),/fx \+ dx \/ d \* ([\d.]+)/,'garrison muzzle radius'),
          garrisonHeight:sourceNumber(BattleClient.prototype._npcMuzzle.toString(),/gy0 \+ ([\d.]+)/,'garrison muzzle height'),
          castDirection:Object.fromEntries([...new Set([...d.castDirF.toString().matchAll(/fx === '([^']+)'/g)].map(match=>match[1]))]
            .map(fx=>[fx,[d.castDirF(fx,false),d.castDirF(fx,true)]]))},
        payloadDuration: sourceNumber(poseWeaponPayloads.toString(), /duration \|\| ([\d.]+)/, 'payload duration'),
        curve: { knee: d.curveKneeM(), inverse: 1 / (2 * d.curveR()) },
        morph: { ...morphHelpers.MORPH_FX,
          damping: sourceNumber(morphSource.morphSwap, /want, ([\d.]+), dt/, 'morph damping'),
          visibleAlpha: sourceNumber(morphSource.morphSide, /a > ([\d.]+)/, 'morph visibility'),
          restoreAlpha: sourceNumber(morphSource.morphSide, /a >= ([\d.]+)/, 'morph material restore'),
          slerpDot: sourceNumber(morphHelpers.slerpQ.toString(), /d > ([\d.]+)/, 'morph near quaternion') },
        shield: { reference: SHIELD_FLASH_REF, expand: SHIELD_PRESENTATION_EXPAND,
          timeWindow: sourceNumber(makeShieldMaterial.toString(), /Math\.random\(\) \* ([\d.]+)/, 'shield phase window'),
          maximum: sourceNumber(shieldHitStrength.toString(), /Math\.min\(([\d.]+)/, 'shield flash cap'),
          base: sourceNumber(shieldHitStrength.toString(), /Math\.min\([^,]+, ([\d.]+)/, 'shield flash base'),
          decay: sourceNumber(stepShieldMaterial.toString(), /decay = ([\d.]+)/, 'shield flash decay') } };
      const bodyTpsMuzzleFallback = [];
      for(const input of [
        {position:[0,0,0],eye:1,bodyYaw:0,camera:[0,1,-bodyRules.tpsMuzzleForward],reach:0,direction:[1,0,0]},
        {position:[12,20,-9],eye:0,bodyYaw:-3.13,camera:[2,3,-5],reach:5,direction:null},
        {position:[12,20,-9],eye:1,bodyYaw:.7,camera:[-6,8,3],reach:100,direction:[2,0,-.5]},
        {position:[12,20,-9],eye:1,bodyYaw:3.13,camera:[-6,8,3],reach:0,direction:[0,0,0]}
      ]) {
        const direction=input.direction?new THREE.Vector3(...input.direction):null;
        const context={viewMode:'tps',bodyYaw:input.bodyYaw,pos:new THREE.Vector3(...input.position),
          _eyeH:()=>input.eye,camera:{position:new THREE.Vector3(...input.camera)},ents:new Map()};
        const origin=BattleClient.prototype._selfMuzzle.call(context,direction,input.reach,'missing');
        bodyTpsMuzzleFallback.push({...input,slot:'missing',result:{origin:origin.toArray(),direction:direction?.toArray()??null}});
      }
      const bodyShield = [];
      for (const drop of [-100, 0, 12, 80, 1000]) {
        const material = makeShieldMaterial(0x4090ff); material.uniforms.uTime.value = 3;
        material.uniforms.uFlash.value = shieldHitStrength(drop);
        const steps = [];
        for (const delta of [0, .016, .1, 1, 2]) {
          stepShieldMaterial(material, delta);
          steps.push({delta, time: material.uniforms.uTime.value, flash: material.uniforms.uFlash.value});
        }
        bodyShield.push({drop, strength: shieldHitStrength(drop), steps}); material.dispose();
      }
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
      const companionGraphs = {}, companionProfiles = {}, companionGeometry = [];
      const hazardGraphs = {}, hazardProfiles = {};
      const lootGraphs = {}, lootProfiles = {}, lootVisuals = [];
      const mineVisuals = [];
      const sceneCollapsePoses = [];
      const airdropVisuals = [];
      const fireVisuals = [];
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
          if (material.isShaderMaterial) {
            if (material.vertexShader !== shieldTemplate.vertexShader || material.fragmentShader !== shieldTemplate.fragmentShader)
              throw new Error('Unsupported source body shader: ' + material.name);
            const index = materials.length; materialIds.set(material, index);
            const uniforms = material.uniforms;
            materials.push({ type: 'shield', color: 0, opacity: 1, transparent: true, blending: material.blending,
              depthTest: material.depthTest, depthWrite: material.depthWrite, side: material.side, texture: -1,
              flipY: false, repeat: [1, 1], offset: [0, 0],
              patternFlipY: uniforms.uPattern.value?.flipY ?? false,
              uniforms: Object.fromEntries(Object.entries(uniforms).map(([key, uniform]) => [key,
                key === 'uPattern' ? textureOf(uniform.value) : uniform.value?.isColor ? uniform.value.toArray() : uniform.value])) });
            return index;
          }
          if (!material.color || material.isShaderMaterial) throw new Error(`Unsupported cockpit material: ${material.type}`);
          const index = materials.length;
          materialIds.set(material, index);
          materials.push({ color: material.color.getHex(), opacity: material.opacity, transparent: material.transparent,
            blending: material.blending, depthTest: material.depthTest, depthWrite: material.depthWrite,
            side: material.side, unshaded: !!material.isMeshBasicMaterial, roughness: material.roughness ?? 1,
            metalness: material.metalness ?? 0, emission: material.emissive?.getHex() || 0,
            emissionIntensity: material.emissiveIntensity ?? 0, texture: textureOf(material.map),
            flipY: material.map?.flipY ?? false, repeat: material.map?.repeat.toArray() || [1, 1],
            offset: material.map?.offset.toArray() || [0, 0], dissolve:!!material.userData?.celDisU,
            alphaTest:material.alphaTest||0 });
          return index;
        };
        const meshOf = geometry => {
          if (meshIds.has(geometry)) return meshIds.get(geometry);
          const index = meshes.length;
          meshIds.set(geometry, index);
          meshes.push({ position: Array.from(geometry.attributes.position.array),
            color: geometry.attributes.color ? Array.from(geometry.attributes.color.array) : [],
            normal: geometry.attributes.normal ? Array.from(geometry.attributes.normal.array) : [],
            uv: geometry.attributes.uv ? Array.from(geometry.attributes.uv.array) : [],
            indices: geometry.index ? Array.from(geometry.index.array) : [], groups: geometry.groups });
          return index;
        };
        const instancesOf = node => {
          const matrix = new THREE.Matrix4();
          return Array.from({length:node.count}, (_, index) => { node.getMatrixAt(index, matrix); return matrix.toArray(); });
        };
        const nodes = all.map((node, id) => {
          node.updateMatrix();
          const result = { id, parent: ids.get(node.parent) ?? -1, name: node.name,
            matrix: node.matrix.toArray(), visible: node.visible, rotationOrder: node.rotation.order };
          result.trs = { p: node.position.toArray(), q: node.quaternion.toArray(), s: node.scale.toArray(), r: [node.rotation.x, node.rotation.y, node.rotation.z] };
          result.flags = Object.fromEntries(['teamRing', 'isOutline', 'noOutline', 'noPaint', 'weatherScorch', 'noViewOcclusion', 'presentationEffect'].map(key => [key, !!node.userData[key]]));
          result.flags.materialArray=Array.isArray(node.material);
          result.flags.skinned=!!node.isSkinnedMesh;
          if (node.isMesh) {
            result.mesh = meshOf(node.geometry);
            result.castShadow = !!node.castShadow;
            result.materials = (Array.isArray(node.material) ? node.material : [node.material]).map(materialOf);
            if (node.isInstancedMesh) {
              result.instances = instancesOf(node);
              if (node.instanceColor) {
                const color = new THREE.Color();
                result.instanceColors = Array.from({length:node.count}, (_, index) => { node.getColorAt(index, color); return color.toArray(); });
              }
            }
            node.geometry.computeBoundingBox();
            if (node.isInstancedMesh) node.computeBoundingBox();
            const box = (node.isInstancedMesh ? node.boundingBox : node.geometry.boundingBox).clone().applyMatrix4(node.matrixWorld);
            result.worldBounds = [box.min.toArray(), box.max.toArray()];
          } else if (!node.isGroup && !node.isBone && node.type !== 'Object3D') throw new Error(`Unsupported cockpit node: ${node.type}`);
          return result;
        });
        return { data: { nodes, meshes, materials, textures }, ids, materialIds, materialOf, instancesOf };
      };
      const captureBodies = new Function('return ' + bodyCaptureSource)();
      const captureAnatomy = new Function('return ' + anatomyCaptureSource)();
      const captureFrames = new Function('return ' + frameCaptureSource)();
      const captureNpc = new Function('return ' + npcCaptureSource)();
      const captureClone = new Function('return ' + cloneCaptureSource)();
      const captureCarrier = new Function('return ' + carrierCaptureSource)();
      const bodies = captureBodies({ THREE, d, makeUnit, graphOf, fireReferenceWeapon, poseWeaponPayloads, stepUnitSpinners,
        fireUnitMotion, stepUnitMotion, stepCombatFx, morphMethods, morphHelpers, gaitMethods, castRules, captureAnatomy, anatomyHelpers,
        captureFrames, captureNpc, captureClone, captureCarrier, NPC_MODEL_KINDS, SUMMON_BUILDERS, measure, unitShotStyle, unitMotion, combatAsset, stepLocomotion, BattleClient, castRemote, cameraProfiles, disposeTree });
      const captureCivilian=new Function('return '+civilianCaptureSource)();
      const civilians=captureCivilian({THREE,d,methods:civilianMethods,geo,limbChain,finishUnitSurfaces,sceneryGeometry,
        generateCivilian,options:CIVILIAN_OPTIONS,kits:CIVILIAN_PROFESSION_KITS,outlinify,enableDissolve:toon.enableDissolve,makeUnit,graphOf,measure,
        stepCombatFx,stepLocomotion,disposeTree});
      const captureBodyView=new Function('return '+viewCaptureSource)();
      const bodyView=captureBodyView({THREE,d,BattleClient,lod});
      const npcShotPoints=[];
      const reportY=new Function('target','return '+npcTargetYExpression);
      const companionY=new Function('target','return '+npcCompanionYExpression);
      const shotPoint=new Function('THREE','ev','tx','tz','return function(){'+npcShotPointDeclaration+'return to;}');
      for(const quantized of [false,true])for(const kind of ['soldier','heli','decoy','robot'])for(const altitude of [-1.5,-.5,0,.5,2.5,30]) {
        const target={kind,hero:kind==='robot',decoy:kind==='decoy',y:altitude};
        const point=shotPoint(THREE,{ty:quantized?reportY(target):companionY(target)},12,-9).call({terrain:{heightAt:()=>20}});
        npcShotPoints.push({position:[12,200,-9],ground:20,altitude,quantized,raised:!quantized||!!(target.hero||target.decoy||kind==='heli'),result:point.toArray()});
      }
      const projectileGraphs = {}, projectileProfiles = {}, projectileGeometry = [], projectileFx = [];
      const captureNpcShots=new Function('return '+shotCaptureSource)();
      const npcShots=captureNpcShots({THREE,d,BattleClient,fx,definitions:shotDefinitions,limits:shotLimits,setLowPower,graphOf,disposeTree});
      Object.assign(projectileGraphs,npcShots.projectiles);Object.assign(projectileProfiles,npcShots.profiles);
      projectileGeometry.push(...npcShots.geometry);projectileFx.push(...npcShots.projectileFx);
      const captureHeroShots=new Function('return '+heroShotCaptureSource)();
      const heroShots=captureHeroShots({THREE,d,assets:COMBAT_ASSETS,fx,BattleClient,source:heroShotSource,
        sampleKeys:combatAsset.sampleCombatKeys,graphOf,disposeTree,setLowPower,limits:shotLimits});
      Object.assign(projectileGraphs,heroShots.projectiles);Object.assign(projectileProfiles,heroShots.profiles);
      projectileGeometry.push(...heroShots.geometry);projectileFx.push(...heroShots.projectileFx);
      const remoteShots=new Function('return '+remoteShotCaptureSource)()({THREE,d,BattleClient});
      const fanFallbacks=new Function('return '+fanFallbackCaptureSource)()({THREE,d,BattleClient});
      const sprites=new Function('return '+spriteCaptureSource)()({THREE,BattleClient,limits:shotLimits,fx});
      const destruction=new Function('return '+destructionCaptureSource)()({THREE,d,toon,sceneDamage,fx,BattleClient,mapBuilding,flameGeometry,setLowPower,graphOf,disposeTree,limits:shotLimits});
      Object.assign(npcShots.graphs,destruction.graphs);
      Object.assign(projectileGraphs,destruction.projectileGraphs);
      Object.assign(projectileProfiles,destruction.projectileProfiles);
      const deathSequences=new Function('return '+deathSequenceCaptureSource)()({THREE,d,BattleClient});
      const deathOverlay=new Function('return '+deathOverlayCaptureSource)()({css:hurtCss});
      const firstPersonShields=new Function('return '+firstPersonShieldCaptureSource)()({THREE,d,BattleClient,fx,
        setupSource:firstPersonShieldSetup,graphOf,disposeTree,characterCombatStyle,characterShieldTexture});
      const hurt=new Function('return '+hurtCaptureSource)()({css:hurtCss,reflashSource});
      const blood=new Function('return '+bloodCaptureSource)()({THREE,d,BattleClient});
      const splatPaint=new Function('return '+splatPaintCaptureSource)()({css:hurtCss,mainSource:mainUiSource});
      const shotColors = Object.fromEntries(['STEEL','SWARM','SUPER'].map(side=>[side,BattleClient.prototype._shotCols(side)]));
      for (const [character,hero] of Object.entries(d.CHARACTERS)) for (const slot of ['light','heavy']) {
        for (const side of ['STEEL','SWARM','SUPER']) {
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
      for(const side of ['GUER','MILI'])for(const kind of [...new Set(['bunker',...d.THIRD.COMP[side]])]) {
        const key=`${side.toLowerCase()}_${kind}`,modelKey=kind==='bunker'?'bunker':`creep:${kind}`;
        const body=makeUnit(modelKey,side,{ring:true}).group;
        body.updateMatrixWorld(true);
        const graph=graphOf(body,true).data,dimensions=capture('',kind,side,modelKey);
        geometry.units[kind]??={};geometry.units[kind][side]=dimensions;
        companionGraphs[key]=graph;
        companionProfiles[key]={kind,side,modelKey,radius:d.hitR({kind,side}),height:d.hitH({kind,side}),dimensions};
        companionGeometry.push({key,meshes:graph.nodes.filter(n=>n.mesh!=null).map(n=>({id:n.id,bounds:n.worldBounds})),profile:companionProfiles[key],dimensions});
        disposeTree(body);
      }
      for(const side of ['SWARM','STEEL'])for(let profession=0;profession<d.CIVILIANS.length;profession++) {
        const key=`${side.toLowerCase()}_civilian_${String(profession).padStart(2,'0')}`,body=makeUnit('civ',side,{ch:profession,appearanceSeed:0,ring:true}).group;
        body.updateMatrixWorld(true);
        const graph=graphOf(body,true).data;
        const dims=measure(THREE,body,'civ',{k:'civilian',s:side,pf:profession},true,new Map());
        const dimensions={top:dims.dimTop,height:dims.dimH,radius:dims.dimR,centre:dims.dimTop-dims.dimH/2};
        companionGraphs[key]=graph;
        companionProfiles[key]={kind:'civilian',side,profession,seed:0,body:d.civilianBody(0),radius:d.hitR({kind:'civilian',civ:true,id:0}),height:d.hitH({kind:'civilian',civ:true,id:0}),dimensions};
        companionGeometry.push({key,meshes:graph.nodes.filter(n=>n.mesh!=null).map(n=>({id:n.id,bounds:n.worldBounds})),profile:companionProfiles[key],dimensions});
        disposeTree(body);
      }
      for (const kind of ['drone_wingman','assault_rover','heli_squad','main_battle_tank','veteran_squad','carnival_heli','decoy_beacon','decoy','hyper']) {
        geometry.units[kind] = {};
        // Source UNIT_KEYS renders the hologram with the dedicated wingman body.
        const modelKey = ['decoy','hyper'].includes(kind) ? kind : `summon:${kind === 'decoy_beacon' ? 'drone_wingman' : kind}`;
        for (const side of ['STEEL','SWARM','SUPER']) {
          const key = `${side.toLowerCase()}_${kind}`;
          const body = makeUnit(modelKey, side, {ring:!['decoy','hyper'].includes(kind)}).group;
          body.updateMatrixWorld(true);
          const graph = graphOf(body,true).data;
          companionGraphs[key] = graph;
          companionProfiles[key] = {kind,side,modelKey,radius:d.hitR({kind,side}),height:d.hitH({kind,side})};
          geometry.units[kind][side] = capture('',kind,side,modelKey);
          companionProfiles[key].dimensions = geometry.units[kind][side];
          companionGeometry.push({key,meshes:graph.nodes.filter(n=>n.mesh != null).map(n=>({id:n.id,bounds:n.worldBounds})),
            profile:companionProfiles[key],dimensions:geometry.units[kind][side]});
          disposeTree(body);
        }
      }
      for (const [character,hero] of Object.entries(d.CHARACTERS)) {
        for (const side of ['STEEL','SWARM','SUPER']) {
          const key=`${side.toLowerCase()}_${character}_kami`,modelKey='hero:drone';
          const body=makeUnit(modelKey,side,{ch:character,ring:false}).group;
          body.scale.setScalar(d.SQUAD.KAMI.SIZE_F);
          body.updateMatrixWorld(true);
          const dims=measure(THREE,body,modelKey,{k:'kami',ch:character,s:side},false,new Map());
          const dimensions={top:dims.dimTop,height:dims.dimH,radius:dims.dimR,centre:dims.dimTop-dims.dimH/2};
          const graph=graphOf(body,true).data;
          companionGraphs[key]=graph;
          companionProfiles[key]={kind:'kami',side,character,modelKey,radius:d.hitR({kind:'kami',ch:character}),height:d.hitH({kind:'kami',ch:character}),dimensions};
          companionGeometry.push({key,meshes:graph.nodes.filter(n=>n.mesh != null).map(n=>({id:n.id,bounds:n.worldBounds})),
            profile:companionProfiles[key],dimensions});
          disposeTree(body);
        }
      }
      for(const key of [...Object.keys(d.HAZARDS),'aasite','relay','fire_lightning']) {
        const kind=key==='fire_lightning'?'fire':key, radius=key==='fire_lightning'?WEATHER_SURFACE.strikeR:(d.HAZARDS[kind]?.r??6);
        const body=buildHazard(kind,0,radius);body.updateMatrixWorld(true);
        const graph=graphOf(body,true);
        graph.data.fireFx={flames:(body.userData.flames||[]).map(node=>({id:graph.ids.get(node),height:node.userData.h0,phase:node.userData.ph,
          origin:node.userData.fireOrigin.toArray(),scale:node.userData.fireScale.toArray(),opacity:node.userData.fireOpacity})),
          smoke:(body.userData.smoke||[]).map(node=>({id:graph.ids.get(node),origin:node.userData.fireOrigin.toArray(),scale:node.userData.fireScale.toArray(),opacity:node.userData.fireOpacity}))};
        const bounds=new THREE.Box3().setFromObject(body);
        const dimensions={radius:Math.max(1,(bounds.max.x-bounds.min.x)/2,(bounds.max.z-bounds.min.z)/2),
          height:Math.max(1,bounds.max.y-bounds.min.y),top:Math.max(1,bounds.max.y),centre:(bounds.min.y+bounds.max.y)/2};
        hazardGraphs[key]=graph.data;hazardProfiles[key]={kind,seed:0,radius,dimensions,fx:graph.data.fireFx};
        if(!graph.data.fireFx.flames.length&&!graph.data.fireFx.smoke.length) {disposeTree(body);continue;}
        for(const now of [0,.125,1,3.7])for(const weather of [{rain:0,snow:0,wind:0,windDir:[1,0]},
          {rain:0,snow:0,wind:100,windDir:[.6,-.8]}, {rain:77.5,snow:0,wind:0,windDir:[1,0]}, {rain:100,snow:0,wind:100,windDir:[1,0]}]) {
          stepFireVisual(body,now,d.fireDotMul(weather),weather);
          const state=nodes=>nodes.map(node=>({id:graph.ids.get(node),visible:node.visible,position:node.position.toArray(),scale:node.scale.toArray(),
            rotation:node.rotation.toArray().slice(0,3),opacity:node.material.opacity}));
          fireVisuals.push({key,now,weather,flames:state(body.userData.flames||[]),smoke:state(body.userData.smoke||[])});
        }
        disposeTree(body);
      }
      const collapseKind=Object.keys(d.SCENE_STRUCT.TYPE)[0];
      for(const id of [42,43])for(const instant of [false,true]) {
        const body=buildHazard(collapseKind,id,d.HAZARDS[collapseKind].r);
        const scale=[1.2,1.7,.9],rotation=[.13,.21,-.17];
        body.scale.fromArray(scale);body.rotation.set(...rotation);
        const ent={id,kind:collapseKind,mesh:body,collapsed:false,colR:12,colH:6,dimH:6,dimR:12};
        const client={effects:[],damaged:new Set(),scene:new THREE.Scene()};
        BattleClient.prototype._applyCollapse.call(client,ent,instant);
        for(const remaining of instant?[0]:[1,.75,.5,.1,0]) {
          if(!instant)client.effects[0].fade(client.effects[0].obj,remaining);
          sceneCollapsePoses.push({id,scale,rotation,progress:instant?1:1-remaining**2,
            result:{scale:body.scale.toArray(),rotation:body.rotation.toArray().slice(0,3)},radius:ent.colR,height:ent.colH});
        }
        disposeTree(body);for(const effect of client.effects)disposeTree(effect.obj);
      }
      const mine=buildMineBump(),mineGraph=graphOf(mine,true).data;
      hazardGraphs.mine_bump=mineGraph;hazardProfiles.mine_bump={kind:'mine_bump',imagery:false};
      mine.position.set(0,.05,0);
      const mineClient={mineMeshes:new Map([[1,mine]]),_mineCheckAt:-100,pos:new THREE.Vector3()};
      const M=d.GAME.MINES;
      for(const [now,x,y] of [[0,M.SEE_M+1,0],[.05,0,0],[.12,M.SEE_M,0],[.24,M.CLEAR_M,0],
        [.36,(M.SEE_M+M.CLEAR_M)/2,0],[.48,0,M.SEE_M+1],[.6,0,.05]]) {
        mineClient.pos.set(x,y,0);BattleClient.prototype._updateMines.call(mineClient,now);
        mineVisuals.push({now,observer:[x,y,0],visible:mine.visible,opacity:mine.material.opacity});
      }
      disposeTree(mine);
      for(const kind of ['cash','ammo','affix']) {
        const body=buildLoot(kind==='ammo',kind==='affix'),graph=graphOf(body,true);
        lootGraphs[kind]=graph.data;lootProfiles[kind]={body:graph.ids.get(body.children[0])};
        body.position.set(12,7,-8);
        const client={lootMeshes:new Map([[1,body]]),flamers:[],envFx:null};
        for(const [delta,now] of [[0,0],[.016,.016],[.125,.141],[1,1.141],[0,12]]) {
          BattleClient.prototype._updateLoot.call(client,delta,now);
          lootVisuals.push({kind,delta,now,rotation:body.rotation.toArray().slice(0,3),body:body.children[0].position.toArray()});
        }
        disposeTree(body);
      }
      for(const size of ['S','M','L']) {
        const key=`airdrop_${size}`,body=buildAirdrop(size),graph=graphOf(body,true);
        lootGraphs[key]=graph.data;lootProfiles[key]=Object.fromEntries(['crate','chute','groundChute','halo'].map(name=>[name,graph.ids.get(body.userData[name])]));
        disposeTree(body);
        for(const landing of [false,true])for(const born of [0,5]) {
          const mesh=buildAirdrop(size);mesh.position.set(12,7,-8);
          Object.assign(mesh.userData,{landing,bornT:born,groundY:7});
          const client={airdropMeshes:new Map([[1,mesh]])};
          const steps=[];
          for(const [delta,age] of [[0,0],[.016,.016],[.784,.8],[.8,1.6],[.125,1.725],[1,2.725]]) {
            const now=born+age;BattleClient.prototype._updateAirdrop.call(client,delta,now);
            steps.push({delta,now,position:mesh.position.toArray(),rotation:mesh.rotation.toArray().slice(0,3),
              nodes:Object.fromEntries(['crate','chute','groundChute','halo'].map(name=>{const node=mesh.userData[name];
                return [name,{visible:node.visible,position:node.position.toArray(),rotation:node.rotation.toArray().slice(0,3)}];}))});
          }
          airdropVisuals.push({size,landing,born,steps});disposeTree(mesh);
        }
      }
      return { geometry, cockpits, cockpitGraphs, projectileGraphs, projectileVisual: {profiles:projectileProfiles,colors:shotColors,beamColors,
        relayDistance:sourceNumber(BattleClient.prototype._tryFire.toString(),/muzzle\.x \+ dir\.x \* ([\d.]+)/,'remote physical launch tracer distance')}, cockpitRules: { ...COCKPIT, kickDecay, flash:flashRules },
        hazardGraphs,hazardProfiles,
        lootGraphs,lootProfiles,
        companionGraphs, companionProfiles, bodyGraphs: bodies.graphs, bodyProfiles: bodies.profiles, bodyRules,
        civilianGraphs:civilians.graphs,civilianVisuals:{profiles:civilians.profiles,rings:civilians.rings},
        npcEffectGraphs:npcShots.graphs,npcShots:{...npcShots.rules,shapes:Object.fromEntries(Object.keys(npcShots.graphs).map(key=>[key,{}]))},sparkPng:npcShots.sparkPng,
        weaponEffectGraphs:heroShots.graphs,weaponEffects:{shapes:heroShots.shapes,characters:heroShots.characters},
        spriteTextures:{...sprites.textures,...destruction.textures},destruction:destruction.rules,
        deathOverlay:deathOverlay.rules,
        firstPersonShieldGraphs:firstPersonShields.graphs,firstPersonShields:firstPersonShields.profiles,
        hurtPresentation:hurt.rules,
        splatPaint:splatPaint.rules,
        fixtures: { ...bodies.fixtures, ...npcShots.fixtures, ...heroShots.fixtures, ...remoteShots, ...fanFallbacks, ...sprites.fixtures, ...destruction.fixtures, ...deathSequences, ...deathOverlay.fixtures, ...firstPersonShields.fixtures, ...hurt.fixtures, ...blood, ...splatPaint.fixtures, bodyViewFrames:bodyView.frames, laneSurfaceProfiles:bodyView.laneProfiles, civilianBodyGeometry:civilians.fixtures, bodyShield, bodyPresentationLod, bodyCastDirection, bodyTpsMuzzleFallback, npcShotPoints, modelCentres, cockpitMuzzles, cockpitPoses, cockpitVisibility, cockpitElevation, weaponPresentation, cockpitFlash, authorityWeaponPoses, burstWeaponPoses, muzzleLaunches, projectileGeometry, projectileFx, companionGeometry,fireVisuals,lootVisuals,mineVisuals,sceneCollapsePoses,airdropVisuals }, glowPng: glowTexture().image.toDataURL('image/png').split(',')[1] };
    }, { dimensionBody, aimBody: method('_entAimPoint'), poseBody, kickDecay: Number(kickDecay[1]), elevationBody, flashBody, flashRules, cameraProfiles, beamColors,
      bodyCaptureSource: captureBodyReferences.toString(), anatomyCaptureSource:captureAnatomicalReferences.toString(),
      frameCaptureSource:captureBodyFrames.toString(), npcCaptureSource:captureNpcBodyReferences.toString(),
      cloneCaptureSource:captureCloneBodyReferences.toString(),carrierCaptureSource:captureCarrierBodyMotion.toString(),
      civilianCaptureSource:captureCivilianBodies.toString(),civilianMethods,
      viewCaptureSource:captureBodyViewReferences.toString(),
      shotCaptureSource:captureNpcShotReferences.toString(),shotDefinitions,shotLimits,
      heroShotCaptureSource:captureHeroShotReferences.toString(),heroShotSource,
      fanFallbackCaptureSource:captureFanFallbackReferences.toString(),
      spriteCaptureSource:captureSpriteReferences.toString(),
      destructionCaptureSource:`function(args) { const captureDestruction=${captureDestruction.toString()}; const captureSceneDamage=${captureSceneDamage.toString()}; const captureMobileDamage=${captureMobileDamage.toString()}; const captureDamageFx=${captureDamageFx.toString()}; const captureMissilePresentation=${captureMissilePresentation.toString()}; const captureBodyRemoval=${captureBodyRemoval.toString()}; const captureDissolve=${captureDissolve.toString()}; const result=captureDestruction(args); const damage=captureDamageFx(args); const missiles=captureMissilePresentation(args); const removal=captureBodyRemoval(args); const dissolve=captureDissolve(args); Object.assign(result.graphs,damage.graphs,missiles.graphs); Object.assign(result.textures,damage.textures); result.projectileGraphs=missiles.projectileGraphs; result.projectileProfiles=missiles.profiles; result.rules.damageFx=damage.rules; result.rules.missilePresentation=missiles.metadata; result.rules.removal=removal.rules; result.rules.dissolve=dissolve.rules; Object.assign(result.fixtures,captureSceneDamage(args),captureMobileDamage(args),damage.fixtures,missiles.fixtures,removal.fixtures,dissolve.fixtures); return result; }`,
      deathSequenceCaptureSource:captureDeathSequences.toString(),deathOverlayCaptureSource:captureDeathOverlay.toString(),
      firstPersonShieldCaptureSource:captureFirstPersonShields.toString(),firstPersonShieldSetup,
      hurtCaptureSource:captureHurtOverlay.toString(),hurtCss,reflashSource,
      bloodCaptureSource:captureBloodSplats.toString(),
      splatPaintCaptureSource:captureSplatPaint.toString(),mainUiSource,
      remoteShotCaptureSource:captureRemoteShotReferences.toString(),
      npcTargetYExpression, npcCompanionYExpression, npcShotPointDeclaration, morphSource, gaitSource, combatRules, castRules, castRemote });
    result.fixtures.splatPaintRasters=await captureSplatRasters(page,mainUiSource,hurtCss);
    result.fixtures.deathOverlayRasters=await captureDeathOverlayRasters(page,hurtCss);
    return { ...result, inputs: [...sourceInputs].sort() };
  } finally {
    await browser.close();
  }
}
