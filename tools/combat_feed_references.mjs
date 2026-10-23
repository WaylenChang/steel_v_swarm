import {pathToFileURL} from 'node:url';
import {join} from 'node:path';

// Execute original notice branches. VFX and authority settlement have separate oracles.
export async function combatFeedReferences(d, gameSource, source) {
  const {grabBlock} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const text = gameSource.replace(/\r\n?/g, '\n');
  const dieStart = text.indexOf("      if (ev.kind === 'aasite') {", text.indexOf('\n  _onEvent(ev)'));
  const dieEnd = text.indexOf("    } else if (ev.e === 'collapse')", dieStart);
  const collapseStart = text.indexOf('      if (HAZARDS[ev.kind]) {', dieEnd);
  const collapseEnd = text.indexOf("    } else if (ev.e === 'boom')", collapseStart);
  if (dieStart < 0 || dieEnd <= dieStart || collapseStart < dieEnd || collapseEnd <= collapseStart)
    throw new Error('Missing original death/collapse feed branches');
  // HERO_KINDS is a Set initializer rather than the source audit helper's literal form.
  const heroDeclaration = /const HERO_KINDS = new Set\((\[[^\n]+\])\);/.exec(text);
  if (!heroDeclaration) throw new Error('Missing original feed hero-kind registry');
  const heroKinds = JSON.parse(heroDeclaration[1].replaceAll("'", '"'));
  const heroInit=/^      const hero = [^\n]+/m.exec(grabBlock(text,"if (ev.e === 'die')"))?.[0];
  if (!heroInit) throw new Error('Missing original death notice hero classification');
  const compile = body => new Function('ev', 'HERO_KINDS', 'HAZARDS', 'THIRD', 'SIDES', 'UNITS', 'sideInfo', 'sceneIsPhysical', 'WEATHER_DEBUFFS', 'performance', 'shockRing', 'ECON', 'SUPER_UPG', 'CHARACTERS', body);
  const handlers = {die: compile(heroInit+'\n'+text.slice(dieStart, dieEnd)), collapse: compile(text.slice(collapseStart, collapseEnd))};
  for (const kind of ['burn', 'cleanse', 'heal_aura_start', 'freeze', 'lightning_strike', 'buy', 'assist', 'creepUp', 'penalty', 'wave', 'respawn'])
    handlers[kind] = compile(grabBlock(text, `else if (ev.e === '${kind}')`));
  const startBody = grabBlock(text, "else if (ev.e === 'cast_start')");
  const startEnd = startBody.indexOf('      const wx =');
  const castBody = grabBlock(text, "else if (ev.e === 'cast')");
  const prefixEnd = castBody.indexOf('      const wx =');
  const noticeStart = castBody.indexOf('        const pct =');
  const noticeEnd = castBody.indexOf('        // 立繪演出', noticeStart);
  if (startEnd < 0 || prefixEnd < 0 || noticeStart < prefixEnd || noticeEnd <= noticeStart)
    throw new Error('Missing original cast-start/cast feed seams');
  handlers.cast_start = compile(startBody.slice(1, startEnd));
  handlers.cast = compile(castBody.slice(1, prefixEnd) + '\nif (a) {\n' + castBody.slice(noticeStart, noticeEnd) + '\n}');
  const invoke = (event, own = true) => {
    const messages = [];
    const client = {youId: '17', side: 'STEEL', bodyId: 71, hero: {id: 71}, trauma: 0, hud: {feed: value => messages.push(value)}, envFx: null,
      terrain: {heightAt: () => 0}, scene: {}, effects: []};
    const value = {...event, pid: own ? '17' : '18'};
    const handler = handlers[event.e];
    // Lightning has a visual ring before its feed gate; only that external producer is stubbed.
    handler.call(client, value, new Set(heroKinds), d.HAZARDS, d.THIRD, d.SIDES, d.UNITS, d.sideInfo, d.sceneIsPhysical,
      d.WEATHER_DEBUFFS, {now: () => 1000}, () => {}, d.ECON, d.SUPER_UPG, d.CHARACTERS);
    return messages;
  };
  const strongBurn = /mul >= ([\d.]+)/.exec(grabBlock(text, "else if (ev.e === 'burn')"));
  if (!strongBurn) throw new Error('Missing original strong-burn notice threshold');
  const rules = {die: {}, collapse: {}, private: {}, buy: {}, creep: {}, castStart: {}, cast: {}, heroKinds, strongBurnThreshold: Number(strongBurn[1])};
  const fixtures = [];
  const record = (event, own) => {
    const messages = invoke(event, own);
    fixtures.push({event, own, messages});
    return messages;
  };
  const kinds = [...new Set([...Object.keys(d.UNITS), ...Object.keys(d.HAZARDS), 'civilian', 'decoy', 'unknown'])];
  for (const side of [...Object.keys(d.SIDES), ...Object.keys(d.THIRD.SIDES)]) for (const kind of kinds) {
    // The original hero notice indexes SIDES directly; third-faction hero kinds are not a supported notice path.
    if ((heroKinds.includes(kind) || kind === 'tower' || kind === 'base') && !d.SIDES[side]) continue;
    const key = `${side}:${kind}`;
    rules.die[key] = record({e: 'die', kind, side}, true);
    if (kind === 'decoy') record({e: 'die', kind, side}, false);
  }
  for (const kind of kinds) for (const ev of [false, true])
    rules.collapse[`${kind}:${ev ? 1 : 0}`] = record({e: 'collapse', kind, ev}, true);
  for (const kind of ['cleanse', 'heal_aura_start', 'freeze']) {
    rules.private[kind] = record({e: kind}, true);
    record({e: kind}, false);
  }
  for (const mul of [0, 1, 1.399999, 1.4, 2]) {
    const event = {e: 'burn', mul};
    rules.private[mul >= rules.strongBurnThreshold ? 'burn_strong' : 'burn'] = record(event, true);
    record(event, false);
  }
  rules.private.lightning = record({e: 'lightning_strike', pts: [{id: 71, x: 0, z: 0}]}, true);
  for (const id of [0, 70, 71, '17', '18'])
    record({e: 'lightning_strike', pts: [{id, x: 0, z: 0}, {id: 71, x: 1, z: 2}]}, true);
  for (const [item, maximum] of [...Object.entries(d.ECON.UPGRADES).map(([key, value]) => [key, value.max]), ['super', d.SUPER_UPG.MAX]])
    for (let lvl = 0; lvl <= maximum; lvl++) {
      rules.buy[`${item}:${lvl}`] = record({e: 'buy', item, lvl}, true);
      record({e: 'buy', item, lvl}, false);
    }
  const token = 123456789;
  for (const kind of ['assist', 'penalty']) {
    rules.private[kind] = record({e: kind, v: token}, true).map(value => value.replaceAll(String(token), '{value}'));
    for (const own of [false, true]) for (const v of [0, 1, 157, -3]) record({e: kind, v}, own);
  }
  rules.private.wave = record({e: 'wave', n: token}, true).map(value => value.replaceAll(String(token), '{wave}'));
  rules.private.respawn = record({e: 'respawn', side: 'STEEL'}, true);
  record({e: 'respawn', side: 'SWARM'}, true);
  for (let lane = 0; lane < 5; lane++) for (let lvl = 0; lvl <= d.CREEP_UPG.MAX; lvl++) for (const own of [false, true]) {
    rules.creep[`${lane}:${lvl}:${own ? 1 : 0}`] = record({e: 'creepUp', side: 'STEEL', lane, lvl}, own);
    record({e: 'creepUp', side: 'SWARM', lane, lvl}, own);
  }
  for (const ch of Object.keys(d.CHARACTERS)) for (const slot of ['def', 'atk']) {
    rules.castStart[`${ch}:${slot}`] = record({e: 'cast_start', ch, slot, dur: 1234.5}, true)
      .map(value => value.replaceAll('1234.5', '{duration}'));
    for (const own of [false, true]) for (const dur of [0, .05, .15, .25, .35, .8, 1.2, 2.45])
      record({e: 'cast_start', ch, slot, dur}, own);
    for (const allied of [false, true]) for (const interrupted of [false, true]) {
      const side = allied ? 'STEEL' : 'SWARM';
      rules.cast[`${ch}:${slot}:${allied ? 1 : 0}:${interrupted ? 1 : 0}`] = record({e: 'cast', ch, slot, side, interrupted, frac: .37}, allied)
        .map(value => value.replaceAll('37%', '{percent}%'));
      for (const frac of [0, .005, .0625, .499999, 1]) record({e: 'cast', ch, slot, side, interrupted, frac}, allied);
    }
  }
  return {rules, fixtures: {combatFeed: fixtures}};
}
