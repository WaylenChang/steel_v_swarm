import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { jointReferences } from './joint_references.mjs';

// Offline scalar oracles use the original gait tables, helpers and motion producer.
export async function locomotionReferences(d, source) {
  const load = file => import(pathToFileURL(join(source, file)).href);
  const [{ grabConst, grabFn }, gait, weights] = await Promise.all([
    load('tools/audit_src.mjs'), load('public/js/gaitcurve.js'), load('public/js/animweights.js'),
  ]);
  const [curveText, motionText] = await Promise.all(['gaitcurve.js', 'locomotion.js'].map(async name =>
    (await readFile(join(source, 'public/js', name), 'utf8')).replace(/\r\n?/g, '\n')));
  const literal = name => new Function(grabConst(curveText, name) + '\nreturn ' + name)();
  const number = (body, pattern, label) => {
    const match = pattern.exec(body); if (!match) throw new Error('Missing original locomotion rule: ' + label);
    return Number(match[1]);
  };
  const step = grabFn(motionText, 'stepLocomotion'), phaseText = grabFn(motionText, 'phaseOf');
  const joints = await jointReferences(gait, source, motionText, d.lerpFPS);
  const gaitRules = { curves: literal('CURVES'), humanHip: literal('HUMAN_HIP'), humanArm: literal('HUMAN_ARM'),
    duties: gait.GAIT_DUTY, dutyMin: gait.DUTY_MIN, dutyMax: gait.DUTY_MAX, hipEase: gait.HIP_EASE,
    postures: gait.POSTURE, roles: gait.ROLES, jointNames: gait.JOINT_NAMES, flexGain: gait.FLEX_GAIN,
    dutyEpsilon: number(gait.hipDrive.toString(), /duty <= 0 \? ([\de.-]+)/, 'duty singularity'),
    distalGain: number(gait.jointFlex.toString(), /Math\.pow\(([\d.]+), i - n/, 'distal attenuation') };
  const motionRules = { idleAmplitude:joints.idleAmplitude,
    accelerationReference: number(motionText, /const ACC_REF = ([\d.]+)/, 'acceleration reference'),
    minimumStep: number(step, /if \(dt < ([\d.]+)\) return/, 'hitstop minimum step'),
    velocityRate: number(step, /L\.vx = damp\([^;]+, ([\d.]+), dt\)/, 'world velocity damping'),
    accelerationRate: number(step, /L\.accel = damp\([^;]+, ([\d.]+), dt\)/, 'acceleration damping'),
    phaseSeed: number(phaseText, /let h = (\d+)/, 'phase seed'), phasePrime: number(phaseText, /Math\.imul\(h, (\d+)\)/, 'phase multiplier'),
    phaseModulus: number(phaseText, /% (\d+)\)/, 'phase modulus'), phaseDivisor: number(phaseText, /% \d+\) \/ (\d+)/, 'phase divisor'),
    walkReference: number(step, /walkRef \|\| ([\d.]+)/, 'walk reference'), walkMinimumSpeed: number(step, /speed < ([\d.]+) \? 0/, 'walk stop'),
    walkMinimumRate: number(step, /clamp\(speed \/ ref, ([\d.]+)/, 'walk lower rate'),
    walkMaximumRate: number(step, /clamp\(speed \/ ref, [\d.]+, ([\d.]+)/, 'walk upper rate'),
    walkRate: number(step, /L\.ts = damp\([^;]+, ([\d.]+), dt\)/, 'walk clip damping'),
    weights: { keyOrder: weights.WEIGHT_KEYS, RUN_LO: weights.RUN_LO, RUN_HI: weights.RUN_HI, AIR_BAND_F: weights.AIR_BAND_F } };
  const phase = new Function('return ' + phaseText)();
  const castDrive = new Function('return ' + grabFn(motionText,'castDrive'))();
  const bodyCastDrive = [-1,-.000001,0,.15,.299999,.3,.300001,.45,.3+.7/2.4,.9,1,1.1].map(value=>({value,result:castDrive(value)}));
  const bodyDamping = [-3,0,.5,10].flatMap(rate => [-.2,0,.016,2].map(delta => ({rate,delta,
    friction:d.frictionFPS(rate,delta),result:2+(-3-2)*d.lerpFPS(rate,delta)})));
  const gaitPhases = [-20, -Math.PI * 2, -Math.PI / 2, 0, Math.PI / 2, Math.PI * 2, 20].map(value => ({ value, result: gait.cycleU(value) }));
  const gaitDuties = [...Object.keys(gait.GAIT_DUTY), 'unknown'].flatMap(key => [-1, 0, .3, 1, 2].map(gallop => ({ key, gallop, result: gait.dutyOf(key, gallop) })));
  const gaitHips = [], gaitJoints = [], gaitBounces = [], gaitHumans = [];
  for (const duty of [-1, 0, .3, .5, .62, 1, 2]) {
    const samples = [...new Set([-.01, 0, .1, .3, .5, .9, 1, 1.01,
      duty * gait.HIP_EASE - .000001, duty * gait.HIP_EASE, duty * (1 - gait.HIP_EASE), duty - .000001, duty, duty + .000001])];
    for (const u of samples) {
      gaitHips.push({ u, duty, result: gait.hipDrive(u, duty) });
      gaitHumans.push({ u, duty, result: gait.humanRunPose(u, duty) });
    }
    for (const ph of [-7, -Math.PI / 2, 0, .7, 7]) for (const asym of [-1, 0, .4, 1, 2])
      gaitBounces.push({ ph, duty, asym, result: gait.bodyBounce(ph, duty, asym) });
    for (const role of [...gait.ROLES, 'unknown']) for (const index of [-1, 0, 1, 2, 3, 5]) for (const u of [0, .1, .5, .9, 1])
      gaitJoints.push({ role, index, u, duty, rest: gait.restOf(role, index), result: gait.jointFlex(role, index, u, duty) });
  }
  const gaitProfiles = [], gaitLimbs = [];
  for (const spec of [null, {}, {fore:'unknown',hindRole:'unknown'}, ...gait.POSTURE_KEYS.map(key => ({fore:key,hind:key})),
    {foreRole:'grasp',hindRole:'arthropod'}, {fore:'plantigrade',hind:'digitigrade',reachF:0,lockF:0,bounceF:0},
    {reachF:.5,lockF:2,bounceF:1.5}, {reachF:null,lockF:null,bounceF:null}, {reachF:-1,lockF:-.5,bounceF:0}]) {
    const result = gait.limbProfile(spec), profile = gaitProfiles.length;
    gaitProfiles.push({spec,result});
    for (const side of ['fore','hind']) for (const index of [-1,0,1,2,4]) for (const duty of [.3,.62]) for (const u of [0,duty-.000001,duty,duty+.000001,1]) for (const amplitude of [0,.5,1.5])
      gaitLimbs.push({profile,side,index,duty,u,amplitude,result:gait.limbFlex(result[side],index,u,duty,amplitude)});
  }
  const gate = /if \(dt < [\d.]+\) return;/.exec(step)?.[0];
  const begin = step.indexOf('  let L = ent.loco;'), end = step.indexOf('  if (!rig) return;', begin);
  const damp = /const damp = [^;]+;/.exec(motionText)?.[0], clamp = /const clamp = [^;]+;/.exec(motionText)?.[0], wrap = /const wrapA = [^;]+;/.exec(motionText)?.[0];
  if (!gate || begin < 0 || end < begin || !damp || !clamp || !wrap) throw new Error('Missing original locomotion integration block');
  const jumpPose = new Function('lerpFPS', `${damp} ${clamp} ${grabFn(motionText,'stepJumpPose')} return stepJumpPose;`)(d.lerpFPS);
  const bodyJumpGates=[];
  for(const kind of ['biped','quad','aerial','wheeled','tracked','morph'])for(const morph of [0,.35,.350001])for(const height of [null,0,2]) {
    const initial={airY:1.5,rawY:1.5,aloft:true,peakY:4,morph},state={...initial},rig={kind},entity={heroY:height};
    jumpPose(state,rig,entity,.1);bodyJumpGates.push({initial,rig,entity,delta:.1,result:state});
  }
  const advance = new Function('lerpFPS', 'phaseOf', `${damp} ${clamp} ${wrap}
    return function(ent,dt,px,pz,pyaw) {${gate} const mesh=ent.mesh,walk=mesh.userData.walk;
      ${step.slice(begin,end)} return {speed,yaw_rate:yawRate,forward:vFwd,lateral:vLat};};`)(d.lerpFPS, phase);
  const bodyMotion = [];
  for (const id of ['1','pilot:7','重裝','a🚀b','']) for (const walking of [false,true]) for (const reference of [0,6,20]) {
    const ctx = {id,loco:null,mesh:{position:{x:0,z:0},rotation:{y:0},userData:{walk:walking?{timeScale:1}:null,walkRef:reference}}};
    const steps = []; let previous=[0,0,0],previousYaw=0;
    for (const input of [{delta:0,position:[0,0,0],yaw:0},{delta:.003999,position:[0,0,0],yaw:0},
      {delta:.004,position:[.03,0,-.1],yaw:3.12},{delta:.016,position:[.3,0,-.5],yaw:-3.12},
      {delta:.1,position:[4,0,-2],yaw:-2.7},{delta:.003,position:[4.1,0,-2.1],yaw:-2.6},
      {delta:.1,position:[4.1,0,-2.1],yaw:-2.6},{delta:.1,position:[4.1,0,-2.1],yaw:-2.6},
      {delta:2,position:[4.1,0,-2.1],yaw:Math.PI*5}]) {
      const position=input.position.map(Math.fround);
      ctx.mesh.position.x=position[0];ctx.mesh.position.z=position[2];ctx.mesh.rotation.y=input.yaw;
      const frame=advance(ctx,input.delta,previous[0],previous[2],previousYaw);
      steps.push({...input,position,previous,previousYaw,result:{advanced:!!frame,state:ctx.loco?{...ctx.loco}:null,frame:frame??null,walk:ctx.mesh.userData.walk?.timeScale??null}});
      previous=position;previousYaw=input.yaw;
    }
    bodyMotion.push({id,walking,reference,phase:phase(id),steps});
  }
  const bodyWeights=[];
  const states=[null,{}, {amp:0,speed:20}, {speed:5},{amp:false,speed:5},{amp:null,speed:5},
    ...[-.1,0,.45,.7,.95,1,2].map(amp=>({amp,landK:1.6,morph:2,srg:-1,brk:.4}))];
  for (const state of states) for (const altitude of [-1,0,1,2,3,8]) for (const ground of [0,2]) for (const flies of [false,true]) {
    const rig={top:10,_aim:.8,_chg:-1.3},options={groundY:ground,y:altitude,flies};
    bodyWeights.push({state,rig,options,result:weights.animWeights(state,rig,options)});
  }
  for (const special of ['amp_nan','amp_infinity','priority_zero','invalid_numbers']) {
    const state={speed:5,act:1},rig={top:10,_aim:0,_chg:0},options={top:0,aim:0,charge:0};
    if(special==='amp_nan')state.amp=NaN;
    if(special==='amp_infinity')state.amp=Infinity;
    if(special==='invalid_numbers'){state.amp=NaN;state.speed=Infinity;rig._aim=NaN;options.aim=false;options.charge='1';}
    bodyWeights.push({special,state:JSON.parse(JSON.stringify(state)),rig:JSON.parse(JSON.stringify(rig)),options,result:weights.animWeights(state,rig,options)});
  }
  return {gait:gaitRules,locomotion:motionRules,rotation:joints.rotation,inputs:['public/js/gaitcurve.js','public/js/animweights.js','public/js/locomotion.js','out/forest_review/three.module.js'],
    fixtures:{...joints.fixtures,bodyDamping,bodyCastDrive,bodyJumpGates,gaitPhases,gaitDuties,gaitHips,gaitJoints,gaitBounces,gaitHumans,gaitProfiles,gaitLimbs,bodyMotion,bodyWeights}};
}
