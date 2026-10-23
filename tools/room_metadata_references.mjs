import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function roomMetadataReferences(source, d, controls) {
  const {grabFn, grabMethod, grabBlock} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = (await readFile(join(source, 'server/rooms.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const html = await readFile(join(source, 'public/index.html'), 'utf8');
  const nameSource = grabFn(text, 'sanitizeName');
  const shape = /\.replace\(\/(.+)\/g, ''\)\.trim\(\)\.slice\(0, (\d+)\) \|\| '([^']+)'/.exec(nameSource);
  const placeholder = id => new RegExp('<input id="' + id + '"[^>]*placeholder="([^"]+)"').exec(html)?.[1];
  if (!shape || !placeholder('myName') || !placeholder('roomNameInput')) throw new Error('Missing original room name rules/UI');
  const sanitize = new Function(nameSource + '\nreturn sanitizeName;')();
  const names = {pattern: shape[1].replace('\\w', 'A-Za-z0-9_'), maximum: Number(shape[2]), fallback: shape[3]};
  const inputs = ['', '   ', 'Alpha_09 - Beta', '  指揮官  ', '<script>alert(1)</script>', 'A\tB\nC', '玩家🐈名字🚀',
    'éÉÅßＡＢＣ１２３カタカナ한글', 'abcdefghijklmnopq', '一'.repeat(20), '\u4dff\u4e00\u9fff\ua000', '𠀀漢𠮷字', 'abc\u00a0def', 'one  two   three'];
  const cases = inputs.map(input => ({input, result: sanitize(input)}));
  const create = new Function('m', 'client', 'teamSize', 'BOT_DIFF', 'DEFAULT_BOT_DIFF', 'CTRL_MODES', 'DEFAULT_CTRL_MODE', 'sanitizeName',
    'return (' + grabBlock(text, 'config: {\n            roomName:') + ');');
  const creations = [];
  for (const name of inputs) for (const visibility of [true, false, null, 0, '', [], {}]) {
    const config = create({roomName: name, isPublic: visibility}, {name: 'fixture-host'}, 1, d.BOT_DIFF, d.DEFAULT_BOT_DIFF, controls.modes, controls.defaultMode, sanitize);
    creations.push({name, visibility, roomName: config.roomName, isPublic: config.isPublic});
  }
  const Hub = new Function('setTimeout', 'sanitizeName', 'BOT_DIFF', 'CTRL_MODES', 'return class {\n' + ['attach', 'leaveRoom'].map(key => grabMethod(text, key)).join('\n') + '\n};')(
    () => {}, sanitize, d.BOT_DIFF, controls.modes);
  const programs = [];
  for (const phase of ['room', 'loading', 'game', 'over']) {
    const hub = new Hub();
    const room = {pin: '1234', hostId: 42, phase, config: {roomName: sanitize('start'), isPublic: true, teamSize: 1}, battleConfig: null,
      clients: new Map([[42, {name: 'Alpha', token: 'fixture-a', mode: 'player', connected: true}], [43, {name: 'Beta', token: 'fixture-b', mode: 'spectator', connected: true}]]), bots: new Map()};
    Object.assign(hub, {rooms: new Map([[room.pin, room]]), _nextClientId: 1000, broadcast() {}, log() {}, osmPayload: () => null, stopBattle() {}});
    const connections = ['fixture-a', 'fixture-b'].map(token => {
      const connection = hub.attach(() => {});
      connection.recv({t: 'reattach', token});
      return connection;
    });
    const frames = [];
    for (const operation of [['info', 1, 'denied', false], ['info', 0, '玩家🐈名字', false], ['info', 0, 'abcdefghijklmnopq', true],
      ['info', 0, '', false], ['leave', 0], ['info', 0, 'old-host', true], ['info', 1, 'newHost - 名', true]]) {
      if (operation[0] === 'leave') connections[operation[1]].recv({t: 'leaveRoom'});
      else connections[operation[1]].recv({t: 'setRoomConfig', roomName: operation[2], isPublic: operation[3]});
      frames.push({operation, host: room.hostId, roomName: room.config.roomName, isPublic: room.config.isPublic,
        members: [...room.clients].map(([id, member]) => ({id, name: member.name}))});
    }
    programs.push({phase, frames});
  }
  return {rules: {names}, ui: {room_player_name: placeholder('myName'), room_name: placeholder('roomNameInput')},
    fixtures: {roomNames: cases, roomMetadataCreations: creations, roomMetadataPrograms: programs}, inputs: ['server/rooms.js', 'public/index.html']};
}
