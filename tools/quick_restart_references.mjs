import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function quickRestartReferences(source, d, controls, variant, campaign) {
  const {grabFn} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const {RoomHub} = await import(pathToFileURL(join(source, 'server/rooms.js')).href);
  const main = (await readFile(join(source, 'public/js/main.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const html = await readFile(join(source, 'public/index.html'), 'utf8');
  const label = /class="qr-title">([^<]+)</.exec(html)?.[1];
  const roomName = /roomName: session\.roomName \|\| `([^`]+)`/.exec(grabFn(main, 'quickRestartGame'))?.[1];
  if (!label || !roomName || !roomName.includes('${myName()}')) throw new Error('Missing original quick-restart UI');
  const first = campaign.chapters[0];
  const story = campaign.maps.find(map => map.chapter === first.id && map.side === 'STEEL' && !map.swapped);
  if (!story) throw new Error('Missing original authored quick-restart map');
  const storyVariant = Object.values(story.variants)[0];
  const cases = [{kind: 'normal', variant, side: 'STEEL', character: 't01', superMode: false},
    {kind: 'random', variant, side: 'SWARM', character: null, superMode: false},
    {kind: 'super', variant, side: d.SUPER_SIDE, character: 's01', superMode: true},
    {kind: 'campaign', variant: storyVariant, side: 'STEEL', character: first.STEEL.heroes[0], superMode: false}];
  const programs = [];
  for (const entry of cases) {
    const hub = new RoomHub({urls: () => [], log() {}}), messages = [];
    const connection = hub.attach(message => messages.push(message));
    const cfg = structuredClone(entry.variant.config);
    cfg.super = entry.superMode;
    cfg.env = {...cfg.env, season: cfg.env?.season || 'summer', time: 'day', weather: 'clear', lunarDay: 15};
    const storage = new Map([['svs_prefs', JSON.stringify({unrelated: 'retained'})]]);
    const localStorage = {getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value)};
    const nodes = new Map();
    const $ = id => {
      if (!nodes.has(id)) nodes.set(id, {value: id === 'myName' ? 'Fixture_User' : ''});
      return nodes.get(id);
    };
    const sent = [], app = {youId: connection.id, teamSize: cfg.teamSize, net: {send: message => sent.push(structuredClone(message))}, phaseShown: 'connect'};
    const api = new Function('app', '$', 'localStorage', 'PREFS_KEY', 'DEFAULT_BOT_DIFF', 'syncQuickRestartFab', 'toast',
      'isMapPrepared', 'showLoadingScreen', 'prepareMapCreation', 'buildYield', 'MAP_EVIDENCE_COPY',
      ['loadPrefs', 'savePrefs', 'myName', 'recordGameSession', 'launchQuickRestartBattle', 'quickRestartGame'].map(key => grabFn(main, key)).join('\n') +
      '\nreturn {recordGameSession,launchQuickRestartBattle,quickRestartGame,loadPrefs};')(
      app, $, localStorage, 'svs_prefs', d.DEFAULT_BOT_DIFF, () => {}, () => {}, () => true, () => {}, async () => ({complete: true}), () => {}, {});
    const savedRandom = Math.random, savedInterval = globalThis.setInterval;
    const frames = [];
    let settings;
    try {
      // No source battle clock runs during metadata capture. Population still uses real BattleSim/BotBrain.
      Math.random = () => 0.75;
      globalThis.setInterval = () => 0;
      connection.recv({t: 'createRoom', battleConfig: cfg, teamSize: cfg.teamSize, name: 'Fixture_User', roomName: 'Fixture_Room', isPublic: true,
        botDiff: d.DEFAULT_BOT_DIFF, ctrl: controls.defaultMode});
      const room = [...hub.rooms.values()][0];
      if (!room) throw new Error('Original RoomHub rejected the saved quick-restart map: ' + JSON.stringify(messages.filter(message => message.t === 'error')));
      connection.recv({t: 'pickSide', side: entry.side});
      if (entry.character) connection.recv({t: 'pickChar', ch: entry.character});
      connection.recv({t: 'addBot', side: 'SWARM'});
      connection.recv({t: 'setBotChar', id: 'b1', ch: 's01'});
      connection.recv({t: 'setReady', ready: true});
      connection.recv({t: 'startBattle'});
      settings = {map_index: 0, team_size: room.config.teamSize, room_name: room.config.roomName, ctrl: room.config.ctrl,
        super: entry.superMode, swapped: false, architecture_seed: room.battleConfig.architectureSeed,
        env: {...room.battleConfig.env, bot_difficulty: room.config.botDiff}};
      if (entry.kind === 'campaign') settings.campaign = {index: 0, chapter: first.id, side: 'STEEL', pilot: first.STEEL.heroes[0], swapped: false};
      const capture = phase => {
        const lobby = [...messages].reverse().find(message => message.t === 'sync')?.lobby;
        if (!lobby) throw new Error('Missing original quick-restart lobby publication');
        api.recordGameSession(lobby);
        const players = lobby.clients.map(member => ({peer: member.isBot ? -Number(String(member.id).slice(1)) : member.id,
          side: member.side || '', character: member.ch || '', mode: member.mode || 'player', bot: !!member.isBot, name: member.name}));
        frames.push({phase, players, preferences: structuredClone(api.loadPrefs())});
      };
      if (room.phase !== 'loading') throw new Error('Original quick-restart setup did not reach loading');
      capture('loading');
      connection.recv({t: 'loaded'});
      if (room.phase !== 'game') throw new Error('Original quick-restart setup did not launch');
      capture('game');
    } finally {
      Math.random = savedRandom;
      globalThis.setInterval = savedInterval;
      hub.shutdown();
    }
    const last = structuredClone(api.loadPrefs().lastSession);
    await api.quickRestartGame();
    const creation = sent.pop();
    sent.length = 0;
    api.launchQuickRestartBattle();
    const plan = structuredClone(sent);
    const lobby = [...messages].reverse().find(message => message.t === 'sync').lobby;
    for (const change of [{mode: 'spectator', side: entry.side}, {mode: 'player', side: null}, null]) {
      const observed = structuredClone(lobby);
      const me = observed.clients.find(member => member.id === connection.id);
      if (change) Object.assign(me, change);
      else observed.clients = observed.clients.filter(member => member.id !== connection.id);
      api.recordGameSession(observed);
      frames.push({phase: 'ineligible', players: observed.clients.map(member => ({peer: member.isBot ? -Number(String(member.id).slice(1)) : member.id,
        side: member.side || '', character: member.ch || '', mode: member.mode || 'player', bot: !!member.isBot, name: member.name})), preferences: structuredClone(api.loadPrefs())});
    }
    programs.push({kind: entry.kind, settings, frames, record: last, creation, plan});
  }
  return {ui: {quick_start: label.trim(), quick_room_name: roomName.replace('${myName()}', '%s')}, fixtures: {quickRestartPrograms: programs},
    inputs: ['public/js/main.js', 'public/index.html', 'server/rooms.js', 'public/js/mapRules.js', 'public/js/mapgen.js']};
}
