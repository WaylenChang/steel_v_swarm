import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Offline only. Execute original handlers with DOM/sensor transport scaffolding;
// expected gestures and angles come from source methods, never copied equations.
export async function mobileReferences(gameSource, source) {
  const { grabMethod, grabFn, grabConst } = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const inputs = ['public/js/mobile.js', 'public/js/ctrlmode.js', 'public/js/lookPrefs.js', 'public/js/movePrefs.js', 'public/index.html', 'public/js/main.js', 'public/css/style.css'];
  const [mobile, control, lookPrefs, movePrefs, html, main, css] = await Promise.all(inputs.map(async file => (await readFile(join(source, file), 'utf8')).replace(/\r\n?/g, '\n')));
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const compile = (code, scope, result) => new Function(...Object.keys(scope), code + '\nreturn ' + result)(...Object.values(scope));
  const literal = (name, scope = {}) => {
    const match = new RegExp(`(?:export )?const ${name} = (.*?);`).exec(mobile);
    if (!match) throw new Error('Missing original mobile literal: ' + name);
    return compile(match[0].replace(/^export /, ''), scope, name);
  };
  const LOOK = compile(grabConst(mobile, 'LOOK'), {}, 'LOOK');
  const defaults = compile(grabConst(mobile, 'TOUCH'), {}, 'TOUCH');
  const gyroSources = literal('GYRO_SRC'), gyroSourceLabels = literal('GYRO_SRC_LABEL');
  const sourceClamp = literal('clamp');
  const settingsStart = mobile.indexOf('export const TOUCH_SETTINGS = [');
  const settingsEnd = mobile.indexOf('\n];', settingsStart);
  if (settingsStart < 0 || settingsEnd < settingsStart) throw new Error('Missing original touch settings schema');
  const settings = compile(mobile.slice(settingsStart, settingsEnd + 3).replace(/^export /, ''),
    { GYRO_SRC: gyroSources, GYRO_SRC_LABEL: gyroSourceLabels }, 'TOUCH_SETTINGS');
  const sensitivity = /TOUCH\.gyroSens = clamp\(TOUCH\.gyroSens, ([\d.]+), ([\d.]+)\)/.exec(mobile);
  if (!sensitivity) throw new Error('Missing original sensitivity bounds');
  const module = (text, exported, storage = {}, device = {}) => {
    const localStorage = { getItem: key => storage[key] ?? null, setItem: (key, value) => { storage[key] = String(value); } };
    const window = { localStorage, screen: { width: device.width ?? 1440, height: device.height ?? 900 },
      matchMedia: query => ({ matches: query.includes('coarse') ? !!device.coarse : !device.noHover }) };
    return compile(text.replace(/^export /gm, ''), { window, localStorage, navigator: { maxTouchPoints: device.touch ? 1 : 0 },
      location: { search: '' }, URLSearchParams }, '{' + exported.join(',') + '}');
  };
  const controlNames = ['CTRL_MODES', 'CTRL_MODE_KEYS', 'DEFAULT_CTRL_MODE', 'CTRL_SCHEMES', 'CTRL_SCHEME_KEYS',
    'ctrlPref', 'ctrlMode', 'ctrlScheme', 'ctrlLocked', 'roomCtrlMode', 'setCtrlPref', 'setCtrlScheme', 'setRoomCtrlMode', 'deviceScheme'];
  const controls = module(control, controlNames);
  const lookModule = module(lookPrefs, ['LOOK_PREFS', 'clampBool']);
  const moveModule = module(movePrefs, ['MOVE_PREFS']);
  const buttonTable = {};
  for (const match of html.matchAll(/<button\b([^>]*\bdata-act="([^"]+)"[^>]*)>([\s\S]*?)<\/button>/g)) {
    buttonTable[match[2]] = match[3].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  }
  const buttons = ['shop', 'map', 'gyro', 'special', 'def', 'atk', 'fire', 'jump', 'reload', 'dive', 'menu', 'aim', 'lock', 'swap', 'lefty'].map(action => {
    if (!buttonTable[action]) throw new Error('Missing original touch button: ' + action);
    return { action, label: buttonTable[action] };
  });
  for (const [original, action] of [['civFollow', 'civ_follow'], ['civAway', 'civ_away']]) {
    const match = new RegExp(`btn\\('${original}', '([^']+)'\\)`).exec(main);
    if (!match) throw new Error('Missing original civilian touch button: ' + original);
    buttons.push({ action, label: match[1] });
  }
  const rules = { look: LOOK, touchDefaults: defaults, gyroSources, gyroSourceLabels, settings,
    sensitivity: { min: Number(sensitivity[1]), max: Number(sensitivity[2]) }, mobilLabels: literal('MOBIL_LABEL'),
    modes: controls.CTRL_MODES, modeKeys: controls.CTRL_MODE_KEYS, defaultMode: controls.DEFAULT_CTRL_MODE,
    schemes: controls.CTRL_SCHEMES, schemeKeys: controls.CTRL_SCHEME_KEYS,
    lookPrefs: lookModule.LOOK_PREFS, movePrefs: moveModule.MOVE_PREFS, buttons };
  rules.kindPresentation = {};
  for (const kind of ['', 'mech', 'drone', 'morph', 'robot']) {
    const nodes = Object.fromEntries(['jump', 'special', 'swap', 'dive', 'fire', 'aim', 'shop', 'lock'].map(action => [action, {textContent: '', hidden: false}]));
    const selectors = {'.gb-b .gb-f': 'jump', '[data-act="special"] .gb-f': 'special'};
    const document = {body: {classList: {toggle() {}}}, querySelector: selector => nodes[selectors[selector]],
      querySelectorAll: selector => selector === '.gb-a, .gb-aim, [data-act="shop"], [data-act="lock"]'
        ? ['fire', 'aim', 'shop', 'lock'].map(action => nodes[action])
        : [nodes[/data-act="([^"]+)"/.exec(selector)?.[1]]]};
    new Function('document', 'MOBIL_LABEL', 'return ({' + grabMethod(mobile, 'setKind') + '});')(document, rules.mobilLabels).setKind(kind);
    rules.kindPresentation[kind] = {jump: nodes.jump.textContent, special: nodes.special.textContent, swap: nodes.swap.textContent,
      hidden: Object.fromEntries(Object.entries(nodes).map(([action, node]) => [action, node.hidden]))};
  }

  const powerLabel=/<span class="set-label">([^<]+)<\/span>\s*<button id="setLowPower"/.exec(html);
  if(!powerLabel)throw new Error('Missing original low-power setting label');
  rules.lowPower={label:powerLabel[1]};
  const mirrorSource=grabFn(main,'padMirror');
  const threshold=/cd > ([\d.]+)/.exec(mirrorSource);
  const rotateText=/<div class="tl-rotate" id="tlRotate">([^<]+)<\/div>/.exec(html);
  const rotateSource=grabMethod(mobile.slice(mobile.indexOf('export class TouchControls')),'_bindRotateHint');
  const rotateDelay=/setTimeout\([^\n]+, (\d+)\)/.exec(rotateSource);
  const ok=/--ok:\s*(#[\da-f]+)/i.exec(css),danger=/--danger:\s*(#[\da-f]+)/i.exec(css);
  if(!threshold||!rotateText||!rotateDelay||!ok||!danger)throw new Error('Missing original touch HUD presentation rules');
  rules.touchHud={cooldownThreshold:Number(threshold[1]),rotateText:rotateText[1],rotateSeconds:Number(rotateDelay[1])/1000,
    ok:ok[1],danger:danger[1]};
  const touchMirrors=[];
  for(const cd of [0,.049,.05,.050001,.499999,.5,.500001,1.5,2.5,99.5])for(const ready of [false,true])for(const locked of [false,true])for(const charges of ['','0/3','2/3']) {
    const result={text:'',ready:false,locked:false};
    const badge={set textContent(value){result.text=value;}};
    const button={querySelector:()=>badge,classList:{toggle:(key,value)=>{result[key]=value;}}};
    const original=compile(mirrorSource,{document:{querySelectorAll:()=>[button]}},'padMirror');
    original('def',cd,ready,locked,charges);
    touchMirrors.push({cd,ready,locked,charges,result});
  }
  const touchRotations=[];
  for(const initialPortrait of [false,true]) {
    let portrait=initialPortrait,visible=false,scheduled=0;
    const listeners={},timers=new Map();let timerId=0;
    const element={classList:{add:()=>{visible=true;},remove:()=>{visible=false;}},
      addEventListener:(name,callback)=>{listeners[name]=callback;}};
    const OriginalRotate=compile('class OriginalRotate {'+rotateSource+'}',{
      document:{getElementById:()=>element,body:{classList:{contains:()=>portrait}}},
      window:{addEventListener(){}},setTimeout:(callback,delay)=>{scheduled=delay;timers.set(++timerId,callback);return timerId;},
      clearTimeout:id=>timers.delete(id)
    },'OriginalRotate');
    const original=new OriginalRotate();original._bindRotateHint();
    const steps=[{kind:'initial',portrait,result:{visible,shown:original._rotShown}}];
    for(const step of [{kind:'timeout'},{kind:'resize',portrait:true},{kind:'dismiss'},{kind:'resize',portrait:false},
      {kind:'resize',portrait:true},{kind:'timeout'}]) {
      if(step.kind==='resize'){portrait=step.portrait;original._onRot();}
      if(step.kind==='dismiss')listeners.pointerdown({stopPropagation(){}});
      if(step.kind==='timeout')for(const callback of timers.values())callback();
      steps.push({...step,portrait,result:{visible,shown:original._rotShown}});
    }
    touchRotations.push({initialPortrait,steps,delay:scheduled});
  }
  const mobilePower=[];
  for(const saved of [null,'0','1','true','false','',0,1,false])for(const pad of [false,true]) {
    let touch=pad;
    const storage={value:saved};
    const original=compile(grabFn(mobile,'lowPower')+'\n'+grabFn(mobile,'setLowPower'),{
      LOWP_KEY:literal('LOWP_KEY'),isTouchUI:()=>touch,
      localStorage:{getItem:()=>storage.value,setItem:(_key,value)=>{storage.value=value;}}
    },'{lowPower,setLowPower}');
    const steps=[];
    for(const step of [{kind:'read'},{kind:'scheme',pad:!pad},{kind:'set',on:false},
      {kind:'scheme',pad},{kind:'set',on:true},{kind:'scheme',pad:!pad},{kind:'set',on:true}]) {
      if(step.kind==='scheme')touch=step.pad;
      if(step.kind==='set')original.setLowPower(step.on);
      steps.push({...step,result:original.lowPower(),saved:storage.value});
    }
    mobilePower.push({saved,pad,steps});
  }

  const mobileDevice = [];
  for (const touch of [false, true]) for (const coarse of [false, true]) for (const noHover of [false, true]) {
    for (const size of [[1440, 900], [820, 1500], [821, 1500], [0, 0]]) {
      const device = { touch, coarse, noHover, width: size[0], height: size[1] };
      mobileDevice.push({ ...device, result: module(control, controlNames, {}, device).deviceScheme() });
    }
  }
  const mobilePreferences = [];
  for (const value of [true, false, 1, 0, 'true', 'false', '1', '', null, 2, [], {}]) {
    mobilePreferences.push({ value, result: lookModule.clampBool(value, false) });
  }
  const mobileTouchPreferences = [];
  for (const saved of [{}, { lefty: true }, { lefty: true, screenLefty: false },
    { gyroSens: '.2', lookSens: '8', gyroSrc: 'missing' }, { gyroSens: true, lookSens: null, haptic: 0 },
    { gyroSens: 'invalid', lookSens: '1.6', gyroSrc: 'motion', gyroInvert: 'false' }]) {
    const original = { ...defaults };
    compile(grabFn(mobile, 'loadTouchPrefs') + '\nloadTouchPrefs();', { TOUCH: original, GYRO_SRC: gyroSources, clamp: sourceClamp,
      SETTINGS_KEY: 'touch', localStorage: { getItem: () => JSON.stringify(saved) } }, 'undefined');
    const result = { ...original };
    for (const key of ['gyro', 'gyroInvert', 'lefty', 'screenLefty', 'haptic']) result[key] = !!result[key];
    mobileTouchPreferences.push({ saved, result });
  }
  const mobileModes = [];
  for (const pref of controls.CTRL_MODE_KEYS) for (const device of ['kbm', 'pad']) {
    const original = module(control, controlNames, { svs_ctrl_mode: pref }, { touch: device === 'pad', coarse: true, noHover: true });
    const steps = [];
    for (const step of [{ kind: 'scheme', value: 'pad' }, { kind: 'room', value: 'kbm' }, { kind: 'scheme', value: 'pad' },
      { kind: 'pref', value: 'pad' }, { kind: 'room', value: 'any' }, { kind: 'scheme', value: 'pad' },
      { kind: 'room', value: 'pad' }, { kind: 'pref', value: 'any' }, { kind: 'room', value: 'invalid' },
      { kind: 'scheme', value: 'kbm' }, { kind: 'pref', value: 'invalid' }]) {
      const accepted = step.kind === 'room' ? original.setRoomCtrlMode(step.value) : step.kind === 'pref' ? original.setCtrlPref(step.value) : original.setCtrlScheme(step.value);
      steps.push({ ...step, accepted, result: { pref: original.ctrlPref(), mode: original.ctrlMode(), scheme: original.ctrlScheme(), locked: original.ctrlLocked() } });
    }
    mobileModes.push({ pref, device, steps });
  }

  const touchText = mobile.slice(mobile.indexOf('export class TouchControls'));
  const methods = ['constructor', '_bindLook', '_bindSticks', '_bindStick', '_stickPaint', '_bindButtons', '_tapNear', '_tapOk',
    '_dropTap', '_tickTap', '_setLookFire', '_blocked', 'tick', '_tickLookFire', 'syncBlocked', 'reset', '_haptic'];
  let now = 1000, TOUCH = { ...defaults }, events = [], listeners = {}, elements = {};
  const element = id => elements[id] ??= { dataset: { act: id }, style: {}, classList: { contains: () => false, add() {}, remove() {}, toggle() {} },
    closest() { return this; }, setPointerCapture() {}, getBoundingClientRect: () => ({ left: 0, top: 0, width: 140, height: 140 }),
    addEventListener(type, handler) { (this.listeners ??= {})[type] = handler; } };
  const document = { getElementById: element, querySelectorAll: () => [], body: { classList: { toggle() {} } },
    addEventListener(type, handler) { listeners[type] = handler; } };
  const touchScope = { LOOK, TOUCH, document, performance: { now: () => now }, navigator: { vibrate: milliseconds => events.push({ type: 'haptic', milliseconds }) },
    Gyro: class {}, setTimeout: fn => { fn(); return 1; } };
  const OriginalTouch = compile('let _active = null;\n' + grabFn(mobile, 'capture') + '\nclass OriginalTouch {\n' +
    methods.map(name => grabMethod(touchText, name)).join('\n') + '\n_bindRotateHint() {}\nsetKind() {}\n_syncGyroBtn() {}\n_local() {return false;}\n}', touchScope, 'OriginalTouch');
  const ev = (step, action = '') => ({ pointerId: step.id ?? 1, clientX: step.point?.[0] ?? 0, clientY: step.point?.[1] ?? 0,
    type: step.cancel ? 'pointercancel' : 'pointerup', target: element(action), preventDefault() {}, stopPropagation() {} });
  const tap = (at = 1000, point = [300, 200]) => [{ kind: 'lookDown', at, point }, { kind: 'up', at: at + 20, point }];
  const programs = [
    { name: 'single_drag', steps: [{ kind: 'lookDown', point: [300, 200] }, { kind: 'move', at: 1040, point: [320, 180] }, { kind: 'tick', at: 1400, delta: .04 }, { kind: 'up', at: 1410, point: [320, 180] }] },
    { name: 'clean_double', steps: [...tap(), { kind: 'lookDown', at: 1100, point: [300, 200] }, { kind: 'up', at: 1200, point: [300, 200] }] },
    { name: 'held_double', steps: [...tap(), { kind: 'lookDown', at: 1100, point: [300, 200] }, { kind: 'tick', at: 1229, delta: .03 }, { kind: 'tick', at: 1230, delta: .03 }, { kind: 'up', at: 1240, point: [300, 200] }] },
    { name: 'cancel_look_tap', steps: [{ kind: 'lookDown', point: [300, 200] }, { kind: 'up', at: 1020, point: [300, 200], cancel: true }, { kind: 'lookDown', at: 1100, point: [300, 200] }, { kind: 'move', at: 1110, point: [308, 200] }, { kind: 'reset', at: 1120 }] },
    { name: 'button_taps', steps: [{ kind: 'button', action: 'def', point: [10, 10] }, { kind: 'up', at: 1260, point: [26, 10] }, { kind: 'button', action: 'atk', at: 1400 }, { kind: 'tick', at: 1661, delta: .02 }, { kind: 'up', at: 1670 }, { kind: 'button', action: 'reload', at: 1800 }, { kind: 'up', at: 1810, cancel: true }] },
    { name: 'button_drag', steps: [{ kind: 'button', action: 'def', point: [10, 10] }, { kind: 'move', at: 1010, point: [26.001, 10] }, { kind: 'up', at: 1020, point: [10, 10] }] },
    { name: 'hold_release', steps: [{ kind: 'button', action: 'aim', id: 2 }, { kind: 'button', action: 'jump', id: 3 }, { kind: 'button', action: 'dive', id: 4 }, { kind: 'up', id: 2, at: 1300 }, { kind: 'blocked', at: 1400, value: true }] },
    { name: 'sticks', steps: [{ kind: 'stick', movement: true, id: 2, point: [70, 70] }, { kind: 'move', id: 2, at: 1020, point: [81.2, 70] }, { kind: 'move', id: 2, at: 1040, point: [140, 0] }, { kind: 'stick', movement: false, id: 3, point: [110, 30], at: 1060 }, { kind: 'tick', at: 1080, delta: .02 }, { kind: 'tick', at: 1120, delta: .04 }, { kind: 'up', id: 2, at: 1150, cancel: true }, { kind: 'up', id: 3, at: 1160 }] },
    { name: 'fire_handoff', steps: [...tap(), { kind: 'button', action: 'fire', id: 2, at: 1080 }, { kind: 'lookDown', at: 1100, point: [300, 200] }, { kind: 'tick', at: 1230, delta: .03 }, { kind: 'up', at: 1240, point: [300, 200] }, { kind: 'up', id: 2, at: 1250 }] },
    { name: 'fire_handoff_reverse', steps: [...tap(), { kind: 'button', action: 'fire', id: 2, at: 1080 }, { kind: 'lookDown', at: 1100, point: [300, 200] }, { kind: 'move', at: 1110, point: [308, 200] }, { kind: 'up', id: 2, at: 1120 }, { kind: 'reset', at: 1130 }] },
    { name: 'multiple_fire_buttons', steps: [{ kind: 'button', action: 'fire', id: 2 }, { kind: 'button', action: 'fire', id: 3 }, { kind: 'up', id: 2, at: 1040 }, { kind: 'up', id: 3, at: 1050 }] },
  ];
  for (const gap of [300, 300.001]) for (const distance of [7.999, 8]) {
    programs.push({ name: `threshold_${gap}_${distance}`, steps: [...tap(), { kind: 'lookDown', at: 1020 + gap, point: [300, 200] }, { kind: 'move', at: 1030 + gap, point: [300 + distance, 200] }, { kind: 'up', at: 1040 + gap, point: [300 + distance, 200] }] });
  }
  const touchPrograms = [];
  for (const sensitivity of [.4, 1, 2.5]) for (const program of programs) {
    now = 1000; TOUCH.lookSens = sensitivity; events = []; listeners = {}; elements = {};
    const original = new OriginalTouch({ paused: false, shopOpen: false, _gameOver: false,
      _cmd: (action, on) => events.push({ type: 'command', action, on }), _applyLook: (x, y) => events.push({ type: 'look', change: [x, y] }) });
    const steps = [];
    for (const step of program.steps) {
      now = step.at ?? now; events = []; const event = ev(step, step.action);
      if (step.kind === 'lookDown') original._onLookDown(event);
      else if (step.kind === 'button') original._onBtnDown(event);
      else if (step.kind === 'stick') (step.movement ? original.moveStick : original.lookStick).onDown(event);
      else if (step.kind === 'move') { original._onLookMove(event); original._onBtnMove(event); original.moveStick.onMove(event); original.lookStick.onMove(event); }
      else if (step.kind === 'up') { original._onLookUp(event); original._onBtnUp(event); original.moveStick.onUp(event); original.lookStick.onUp(event); }
      else if (step.kind === 'tick') original.tick(step.delta);
      else if (step.kind === 'reset') original.reset();
      else if (step.kind === 'blocked') { original.client.paused = step.value; original.syncBlocked(); }
      steps.push({ ...step, at: now, events: events.slice(), result: { axis: [original.axis.r, -original.axis.f], lookId: original._lookId ?? -1,
        fireArm: original._fireArm, lookFire: original._lookFire, tapAt: original._tapAt,
        movement: [original.moveStick.x, original.moveStick.y], lookStick: [original.lookStick.x, original.lookStick.y],
        held: Object.fromEntries(original._held), taps: [...original._tap.keys()] } });
    }
    touchPrograms.push({ name: program.name, sensitivity, steps });
  }

  const gyroText = mobile.slice(mobile.indexOf('\nclass Gyro {'), mobile.indexOf('/* ---------------- 現役實例'));
  let angle = 0, timers = new Map(), timerId = 0;
  const gyroScope = { THREE, LOOK, TOUCH, clamp: sourceClamp,
    performance: { now: () => now }, screenAngle: () => angle,
    window: { DeviceMotionEvent: class {}, addEventListener() {}, removeEventListener() {} },
    clearTimeout: id => timers.delete(id), setTimeout: callback => { timers.set(++timerId, callback); return timerId; } };
  const gyroConstants = mobile.slice(mobile.indexOf('\nconst ZEE ='), mobile.indexOf('\n/**', mobile.indexOf('\nconst Q_UP =')));
  const OriginalGyro = compile(gyroConstants + '\nclass OriginalGyro {\n' + ['constructor', '_use', '_unbind', '_emit', '_checkYawDead', '_readOrient', '_readMotion'].map(name => grabMethod(gyroText, name)).join('\n') + '\n}', gyroScope, 'OriginalGyro');
  const gyroPrograms = [];
  const sensorPrograms = [
    { name: 'motion', source: 'motion', steps: [{ kind: 'motion', rate: [30, -20, 0], delta: .016 }, { kind: 'motion', rate: [30, -20, 0], delta: .016 }, { kind: 'motion', rate: [.1, .1, 0], delta: .016 }, { kind: 'motion', rate: [20, 40, 0], delta: 2 }, { kind: 'motion', rate: [1000, 1000, 0], delta: .1 }, { kind: 'motion', rate: [0, 0, 0], delta: .02 }] },
    { name: 'orient', source: 'orient', steps: [{ kind: 'orient', pose: [359, 60, 0] }, { kind: 'orient', pose: [1, 62, 1] }, { kind: 'orient', pose: [170, 40, 2] }, { kind: 'orient', pose: [171, 41, 3] }, { kind: 'reset' }, { kind: 'orient', pose: [40, 60, 0] }, { kind: 'orient', pose: [41, 61, 0] }] },
    { name: 'yaw_fallback', source: 'auto', steps: [{ kind: 'orient', pose: [0, 60, 0] }, { kind: 'orient', pose: [0, 70, 0] }, { kind: 'orient', pose: [0, 80, 0] }, { kind: 'motion', rate: [20, 30, 0], delta: .02 }, { kind: 'motion', rate: [20, 30, 0], delta: .02 }] },
    { name: 'watchdog', source: 'auto', steps: [{ kind: 'watchdog', at: 2600 }, { kind: 'watchdog', at: 4200 }] },
    { name: 'forced_watchdog', source: 'orient', steps: [{ kind: 'watchdog', at: 2600 }] },
  ];
  for (const screenAngle of [0, 90, -90, 180]) for (const invert of [false, true]) for (const sensitivity of [.4, 1, 2.5]) for (const program of sensorPrograms) {
    now = 1000; angle = screenAngle; timers = new Map(); TOUCH.gyroSrc = program.source; TOUCH.gyroSens = sensitivity; TOUCH.gyroInvert = invert;
    const outputs = [], failures = [];
    const original = new OriginalGyro((x, y) => outputs.push([x, y]), () => { original.active = false; failures.push(true); });
    original.active = true; original._use(program.source === 'motion' ? 'motion' : 'orient');
    const steps = [];
    for (const step of program.steps) {
      now = step.at ?? now + 20; outputs.length = 0; failures.length = 0;
      let gravity, magnetic;
      if (step.kind === 'motion') original._readMotion({ rotationRate: { beta: step.rate[0], gamma: step.rate[1], alpha: step.rate[2] }, interval: step.delta * 1000 });
      else if (step.kind === 'orient') {
        original._readOrient({ alpha: step.pose[0], beta: step.pose[1], gamma: step.pose[2] }, 'deviceorientation');
        const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(step.pose[1] * Math.PI / 180, step.pose[0] * Math.PI / 180, -step.pose[2] * Math.PI / 180, 'YXZ'));
        q.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), -Math.PI / 2));
        q.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), -screenAngle * Math.PI / 180));
        const inverse = q.clone().invert();
        gravity = new THREE.Vector3(0, -9.8, 0).applyQuaternion(inverse).toArray();
        magnetic = new THREE.Vector3(0, -14, -32).applyQuaternion(inverse).toArray();
      } else if (step.kind === 'reset') original._reset();
      else if (step.kind === 'watchdog') { const callback = [...timers.values()][0]; timers.clear(); callback?.(); }
      steps.push({ ...step, at: now, gravity, magnetic, outputs: outputs.slice(), failed: failures.length > 0,
        result: { active: original.active, path: original.path, have: original._have, raw: [original._rawYaw, original._rawPitch],
          accumulated: [original.accYaw * Math.PI / 180, original.accPitch * Math.PI / 180], events: original.events, usable: original.usable } });
    }
    gyroPrograms.push({ name: program.name, source: program.source, screenAngle, invert, sensitivity, steps });
  }
  const flightBlock = gameSource.slice(gameSource.indexOf("      const level = movePref('levelMove');"), gameSource.indexOf('\n      // 控場:垂直升降', gameSource.indexOf("      const level = movePref('levelMove');")));
  if (!flightBlock.includes('const target =')) throw new Error('Missing original level-move flight seam');
  let levelMove = false;
  const flight = compile(`function originalFlight(ax,right) {${flightBlock}\nreturn target.toArray();}`, { _TMP_D: new THREE.Vector3(), _TMP_E: new THREE.Vector3(), movePref: () => levelMove }, 'originalFlight');
  const mobileFlight = [];
  for (const yaw of [0, .8, -3]) for (const pitch of [-1.4, 0, 1.4]) for (const level of [false, true]) for (const motion of [[0, -1], [1, 0], [.6, -.8]]) {
    levelMove = level;
    mobileFlight.push({ yaw, pitch, level, motion, result: flight.call({ yaw, pitch }, { f: -motion[1], r: motion[0] }, new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw))) });
  }
  return { rules, inputs, fixtures: { mobileDevice, mobilePreferences, mobileTouchPreferences, mobileModes, mobilePower, touchMirrors, touchRotations, touchPrograms, gyroPrograms, mobileFlight } };
}
