import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function deploymentReferences(source, d) {
  const {grabFn, grabBlock} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const main = (await readFile(join(source, 'public/js/main.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const data = (await readFile(join(source, 'public/js/data.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const venues = await import(pathToFileURL(join(source, 'public/js/venues.js')).href);
  const VENUES = venues.VENUES.filter(venue => !venue.story && venues.venueAvailability(venue, d.TEAM.MAX).available);
  const prefsKey = /const PREFS_KEY = '([^']+)';/.exec(main)?.[1];
  const superName = /sprefs\.superRoomName \|\| '([^']+)'/.exec(grabFn(main, 'enterOpenRoom'))?.[1];
  if (!prefsKey || !superName) throw new Error('Missing original deployment preference seams');
  const difficultyExpression = /botDiff: (isSuper \?[^\n]+),\n/.exec(main)?.[1];
  if (!difficultyExpression) throw new Error('Missing original mode-specific difficulty preference');
  const difficulty = new Function('isSuper', 'loadPrefs', 'DEFAULT_BOT_DIFF', 'return (' + difficultyExpression + ');');
  const programs = [], ui = {};
  const initials = [{}, {teamSize: d.TEAM.MAX, roomName: 'Main', lastVenueId: VENUES[0].id, botDiff: 'low',
    env: {season: 'winter', time: 'night', weather: 'snow'}, lastSide: 'STEEL', lastChar: 't01'},
    {teamSize: d.TEAM.MIN, superTeamSize: d.TEAM.MAX, roomName: 'Main', superRoomName: 'Super', lastVenueId: VENUES[0].id,
      superVenueId: VENUES[1].id, botDiff: 'high', superBotDiff: 'novice', env: {season: 'spring', time: 'dawn', weather: 'rain'}, superEnv: {}},
    {teamSize: 0, superTeamSize: 99, env: {season: 'invalid', time: null, weather: 'invalid'}, superEnv: null}];
  for (const initial of initials) {
    const store = new Map([[prefsKey, JSON.stringify(initial)]]), nodes = new Map();
    const $ = id => {
      if (!nodes.has(id)) nodes.set(id, {value: '', innerHTML: '', children: [], style: {}, parentElement: {style: {}}, querySelectorAll: () => [], querySelector: () => null});
      return nodes.get(id);
    };
    const storage = {getItem: key => store.get(key) ?? null, setItem: (key, value) => store.set(key, value)};
    const app = {teamSize: d.TEAM.DEFAULT, mapSel: null, net: {send() {}}};
    const noop = () => {};
    const factory = new Function('localStorage', 'PREFS_KEY', 'app', '$', 'TEAM', 'ENV', 'VENUES', 'show', 'renderTeamSizeOpen',
      'renderVenuesOpen', 'renderFavsOpenRoom', 'venueAvailability', 'venueConfig', 'triggerBackgroundMapSetup', 'warmModels', 'venueBrief', 'updateTsInfoOpen', 'syncVenueTips', 'showCharDetail',
      ['loadPrefs', 'savePrefs', 'myName', 'esc', 'renderEnvSelects', 'enterOpenRoom', 'setTeamSizeOpen', 'selectVenueOpen', 'selectChar'].map(key => grabFn(main, key)).join('\n') +
      '\nreturn {loadPrefs,savePrefs,myName,enterOpenRoom,setTeamSizeOpen,selectChar};');
    const api = factory(storage, prefsKey, app, $, d.TEAM, d.ENV, VENUES, noop, noop, noop, noop, venues.venueAvailability, venues.venueConfig, noop, noop, () => '', noop, noop, noop);
    const roomInput = new Function('e', 'app', 'savePrefs', grabBlock(main, "$('roomNameInput').addEventListener('input',"));
    const frames = [];
    const enter = superMode => {
      api.enterOpenRoom({isSuper: superMode});
      for (const [key, id] of [['season', 'envSeason'], ['time', 'envTime'], ['weather', 'envWeather']]) {
        ui['room_random_' + key] = /<option value="random">([^<]+)<\/option>/.exec($(id).innerHTML)?.[1];
      }
    };
    const apply = operation => {
      if (operation[0] === 'mode') enter(operation[1]);
      else if (operation[0] === 'team') api.setTeamSizeOpen(operation[1]);
      else if (operation[0] === 'room') {
        $('roomNameInput').value = operation[1];
        roomInput({target: {value: operation[1]}}, app, api.savePrefs);
      } else if (operation[0] === 'env') {
        for (const [key, id] of [['season', 'envSeason'], ['time', 'envTime'], ['weather', 'envWeather']]) $(id).value = operation[1][key];
        $('envSeason').onchange();
      } else if (operation[0] === 'name') { $('myName').value = operation[1]; api.myName(); }
      else if (operation[0] === 'character') {
        Object.assign(app, {pickEditable: true, pickIsSelf: true, pickSide: operation[1]});
        api.selectChar(operation[2]);
      } else if (operation[0] === 'patch') api.savePrefs(operation[1]);
      frames.push({operation, values: api.loadPrefs(), playerName: store.get('svs_name') ?? '',
        selected: {team_size: Number(app.teamSize), room_name: $('roomNameInput').value, venue_id: app.venueSelOpen?.id || '',
          env: {season: $('envSeason').value, time: $('envTime').value, weather: $('envWeather').value},
          bot_difficulty: difficulty(app.isSuperDeploy, api.loadPrefs, d.DEFAULT_BOT_DIFF)}});
    };
    apply(['mode', false]);
    apply(['name', '\u00a0Pilot_A\ufeff']);
    apply(['name', ' \t ']);
    apply(['room', '  Regular  ']);
    apply(['team', d.TEAM.MIN]);
    apply(['env', {season: 'autumn', time: 'dusk', weather: 'windy'}]);
    apply(['character', 'STEEL', 't01']);
    apply(['mode', true]);
    apply(['room', '  Super  ']);
    apply(['team', d.TEAM.MAX]);
    apply(['env', {season: 'spring', time: 'dawn', weather: 'clear'}]);
    apply(['character', 'SUPER', 's01']);
    apply(['mode', false]);
    apply(['patch', {env: {season: 'summer'}, retainedUnknown: {v: 1}}]);
    apply(['mode', false]);
    apply(['mode', true]);
    programs.push({initial, frames});
  }
  if (Object.values(ui).some(value => !value)) throw new Error('Missing original random environment labels');
  const resolved = [], weighted = [];
  let draws = 0, rolls = [];
  const math = Object.create(Math);
  math.random = () => rolls[draws++ % rolls.length];
  const resolve = new Function('ENV', 'SEASON_WEATHER_WEIGHTS', 'Math', grabFn(data, 'pickSeasonalWeather') + '\n' + grabFn(data, 'resolveEnv') + '\nreturn resolveEnv;')(d.ENV, d.SEASON_WEATHER_WEIGHTS, math);
  for (const env of [{}, {season: 'random', time: 'random', weather: 'random'}, ...Object.keys(d.ENV.seasons).map(season => ({season, time: 'day', weather: 'random'})),
    ...[0, 1, 15, 30, 31, 15.5, '15', true].map(lunarDay => ({season: 'winter', time: 'night', weather: 'snow', lunarDay}))]) {
    for (const sequence of [[0, 0, 0, 0], [0.999999, 0.999999, 0.999999, 0.999999], [0.4, 0.2, 0.8, 0.6]]) {
      rolls = sequence;
      draws = 0;
      const result = resolve(env);
      resolved.push({env, rolls: sequence, result, draws});
    }
  }
  for (const season of [...Object.keys(d.SEASON_WEATHER_WEIGHTS), 'invalid']) {
    const weights = d.SEASON_WEATHER_WEIGHTS[season] || d.SEASON_WEATHER_WEIGHTS.summer;
    const total = Object.values(weights).reduce((sum, value) => sum + value, 0);
    let cumulative = 0;
    for (const weight of Object.values(weights)) {
      cumulative += weight;
      for (const roll of [Math.max(0, cumulative / total - 1e-12), cumulative / total]) weighted.push({season, roll, result: d.pickSeasonalWeather(season, roll)});
    }
  }
  return {rules: {deployment: {superRoomName: superName}}, ui, fixtures: {deploymentPrograms: programs, roomEnvironmentResolved: resolved, roomSeasonalWeights: weighted}, inputs: ['public/js/main.js', 'public/js/data.js', 'public/js/venues.js']};
}
