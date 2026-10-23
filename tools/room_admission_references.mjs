import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function roomAdmissionReferences(source, d) {
  const {grabMethod, grabFn} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = (await readFile(join(source, 'server/rooms.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const main = (await readFile(join(source, 'public/js/main.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const html = (await readFile(join(source, 'public/index.html'), 'utf8')).replace(/\r\n?/g, '\n');
  const spectator = /name="joinMode" value="spectator">([^<]+)/.exec(html);
  const title = /\$\('overTitle'\)\.textContent = ot \? ot.title : `([^`]+)`;/.exec(main);
  if (!spectator || !title || !title[1].includes('${win.name}')) throw new Error('Missing original spectator admission/result labels');
  const ui = {room_join_spectator: spectator[1].trim(), room_spectator_result: title[1].replace('${win.name}', '%s')};
  let token = 0;
  const Hub = new Function('setTimeout', 'genToken', grabFn(text, 'sanitizeName') + '\nreturn class {\n' + grabMethod(text, 'attach') + '\n};')(
    () => {}, () => 'fixture-opaque-' + (++token));
  const programs = [];
  for (const capacity of [d.TEAM.MIN, d.TEAM.MAX]) for (const superMode of [false, true]) for (const phase of ['room', 'loading', 'game', 'over']) {
    for (const shape of [{players: 0, spectators: 3, bots: 0}, {players: 1, spectators: 3, bots: 0},
      {players: 1, spectators: 0, bots: capacity * 2 - 1}, {players: capacity * 2, spectators: 2, bots: 0}]) {
      for (const mode of ['player', 'spectator', 'invalid']) {
        const messages = [];
        const hub = new Hub();
        const definitions = [...Array.from({length: shape.players}, (_, index) => ({mode: 'player', side: index % 2 ? 'SWARM' : 'STEEL', connected: index !== 0})),
          ...Array.from({length: shape.spectators}, () => ({mode: 'spectator', side: null, connected: true}))];
        const room = {pin: '1234', phase, hostId: 42, config: {teamSize: capacity}, battleConfig: {super: superMode},
          clients: new Map(definitions.map((value, index) => [42 + index, value])), bots: new Map(Array.from({length: shape.bots}, (_, index) => ['b' + index, {}])),
          battle: phase === 'game' ? {fieldPayload: () => ({t: 'field'})} : null};
        Object.assign(hub, {rooms: new Map([[room.pin, room]]), _nextClientId: 1000, broadcast() {}, osmPayload: () => null});
        const connection = hub.attach(message => messages.push(message));
        connection.recv({t: 'joinRoom', pin: room.pin, mode, name: 'fixture'});
        const member = room.clients.get(connection.id), error = messages.find(message => message.t === 'error')?.msg ?? '';
        let errorKey = '';
        if (error) {
          errorKey = superMode && shape.players > 0 ? 'room_join_super_only' : 'room_join_full_' + (capacity * 2);
          if (ui[errorKey] && ui[errorKey] !== error) throw new Error('Inconsistent original admission notice');
          ui[errorKey] = error;
        }
        programs.push({capacity, superMode, phase, mode, definitions, bots: shape.bots, accepted: !!member, errorKey,
          result: member ? {mode: member.mode, side: member.side ?? '', ready: member.ready, loaded: member.loaded, connected: member.connected} : null,
          prepare: messages.some(message => message.t === 'battleConfig'), field: messages.some(message => message.t === 'field')});
      }
    }
  }
  // Capacity notices are used by every supported native team size.
  for (let capacity = d.TEAM.MIN; capacity <= d.TEAM.MAX; capacity++) {
    if (ui['room_join_full_' + capacity * 2]) continue;
    const hub = new Hub(), messages = [];
    const room = {pin: '1234', config: {teamSize: capacity}, clients: new Map(), bots: new Map(Array.from({length: capacity * 2}, (_, index) => [index, {}]))};
    Object.assign(hub, {rooms: new Map([[room.pin, room]]), _nextClientId: 1000});
    hub.attach(message => messages.push(message)).recv({t: 'joinRoom', pin: room.pin, mode: 'player'});
    const error = messages.find(message => message.t === 'error');
    if (!error) throw new Error('Missing original full-room admission notice');
    ui['room_join_full_' + capacity * 2] = error.msg;
  }
  return {ui, fixtures: {roomAdmission: programs}, inputs: ['server/rooms.js', 'public/js/main.js', 'public/index.html']};
}
