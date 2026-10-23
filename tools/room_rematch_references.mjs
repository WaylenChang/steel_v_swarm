import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function sourceSideSwap(source) {
  const {grabFn} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = (await readFile(join(source, 'server/rooms.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const apply = new Function('cfg', 'Math', grabFn(text, 'rollSideSwap') + '\nrollSideSwap(cfg);');
  return (config, roll) => apply(config, {random: () => roll});
}

export async function roomRematchReferences(source, controls) {
  const {grabMethod, grabFn} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = (await readFile(join(source, 'server/rooms.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const html = await readFile(join(source, 'public/index.html'), 'utf8');
  const label = /id="backRoomBtn"[^>]*>([^<]+)</.exec(html)?.[1];
  if (!label) throw new Error('Missing original return-to-room label');
  const programs = [];
  for (const phase of ['room', 'loading', 'game', 'over']) for (const seed of [0, 4294967295]) {
    let roll = 0.25, stops = 0, broadcasts = 0;
    const math = Object.create(Math);
    math.random = () => roll;
    const Hub = new Function('setTimeout', 'CTRL_MODES', 'Math', grabFn(text, 'rollSideSwap') + '\nreturn class {\n' + grabMethod(text, 'attach') + '\n};')(
      () => {}, controls.modes, math);
    const hub = new Hub(), battle = {fieldPayload: () => ({t: 'field'})};
    const definitions = [{mode: 'player', side: 'STEEL', character: 't01', connected: true},
      {mode: 'spectator', side: null, character: null, connected: true},
      {mode: 'player', side: 'SWARM', character: 's01', connected: false}];
    const room = {pin: '1234', hostId: 42, phase, battle, config: {ctrl: controls.defaultMode},
      clients: new Map(definitions.map((value, index) => [42 + index, {...value, token: 'fixture-' + index, ready: true, loaded: true, send() {}}])),
      bots: new Map([['b1', {side: 'STEEL', name: 'fixture-bot'}]]),
      battleConfig: {architectureSeed: seed, bases: {SWARM: [1, 2], STEEL: [3, 4]}, lanes: [[[1, 2], [3, 4]]], motherLanes: [[[1, 2], [5, 6], [3, 4]]], env: {season: 'winter'}}};
    Object.assign(hub, {rooms: new Map([[room.pin, room]]), _nextClientId: 1000, log() {}, osmPayload: () => null,
      broadcast: () => broadcasts++, stopBattle: () => stops++});
    const connections = [0, 1].map(index => {
      const connection = hub.attach(() => {});
      connection.recv({t: 'reattach', token: 'fixture-' + index});
      return connection;
    });
    stops = 0;
    broadcasts = 0;
    const frames = [];
    const apply = (who, value) => {
      roll = value;
      connections[who].recv({t: 'backToRoom'});
      frames.push({who, roll, phase: room.phase, stops, broadcasts, hasBattle: room.battle !== null,
        config: structuredClone(room.battleConfig),
        members: [...room.clients].map(([id, member]) => ({id, ...definitions[id - 42], ready: member.ready, loaded: member.loaded})),
        bots: [...room.bots].map(([id, value]) => ({id, ...value}))});
    };
    apply(1, 0.25);
    apply(0, 0.25);
    apply(0, 0.5);
    apply(0, 0.499999);
    apply(0, 0.9);
    programs.push({phase, seed, definitions, frames});
  }
  return {ui: {room_return: label.trim()}, fixtures: {roomRematchPrograms: programs}, inputs: ['server/rooms.js', 'public/index.html']};
}
