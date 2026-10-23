import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function roomRecoveryReferences(source) {
  const {grabMethod, grabBlock} = await import(pathToFileURL(join(source, 'tools/audit_src.mjs')).href);
  const net = (await readFile(join(source, 'public/js/net.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const main = (await readFile(join(source, 'public/js/main.js'), 'utf8')).replace(/\r\n?/g, '\n');
  const bound = /this\._queue\.length >= (\d+)/.exec(grabMethod(net, '_queueMsg'));
  if (!bound) throw new Error('Missing original disconnected queue capacity');
  const capacity = Number(bound[1]);
  const Net = new Function('clearTimeout', 'return class {\n' + ['_raw', 'sendNow', 'flushQueue', '_queueMsg', 'send', 'kill'].map(key => grabMethod(net, key)).join('\n') + '\n};')(() => {});
  const programs = [];
  for (const count of [0, 1, capacity - 1, capacity, capacity + 1, capacity * 2 + 1]) for (const failAfter of [-1, 0, 3]) {
    const client = new Net(), sent = [], frames = [];
    let budget = -1;
    Object.assign(client, {connected: false, _queue: [], _later() {}, ws: {send(raw) {
      if (budget === 0) throw new Error('fixture disconnect');
      if (budget > 0) budget--;
      sent.push(JSON.parse(raw));
    }, close() {}}});
    const apply = operation => {
      if (operation[0] === 'connected') client.connected = operation[1];
      else if (operation[0] === 'budget') budget = operation[1];
      else if (operation[0] === 'send') client.send(operation[1]);
      else if (operation[0] === 'now') client.sendNow(operation[1]);
      else if (operation[0] === 'flush') client.flushQueue();
      else if (operation[0] === 'kill') client.kill();
      frames.push({operation, connected: client.connected, pending: structuredClone(client._queue), sent: structuredClone(sent)});
    };
    apply(['now', {kind: 'dropped-immediate', n: -1}]);
    for (let n = 0; n < count; n++) apply(['send', {kind: n % 3 ? 'input' : 'action', n, data: {yaw: n / 10}}]);
    apply(['flush']);
    apply(['connected', true]);
    apply(['budget', failAfter]);
    apply(['flush']);
    apply(['send', {kind: 'after-failure', n: count}]);
    apply(['now', {kind: 'immediate-race', n: count + 1}]);
    apply(['budget', -1]);
    apply(['connected', true]);
    apply(['flush']);
    apply(['send', {kind: 'live', n: count + 2}]);
    apply(['connected', false]);
    apply(['send', {kind: 'cancelled', n: count + 3}]);
    apply(['kill']);
    // Net.kill does not rewrite connected; _dead prevents further reconnect work.
    programs.push({count, failAfter, frames});
  }
  const reconnect = new Function('app', 'sessionStorage', 'fatal', grabBlock(main, 'reconnect: () =>'));
  const recoveries = [];
  for (const token of [null, '', 'fixture-token']) {
    const order = [], fatal = {};
    reconnect({net: {sendNow: message => order.push(message), flushQueue: () => order.push({t: 'flush'})}}, {getItem: () => token}, fatal);
    recoveries.push({token, order});
  }
  const sync = /app\.token = m\.token;\n\s*sessionStorage\.setItem\('([^']+)', m\.token\);/.exec(main);
  const invalid = grabBlock(main, 'error: (m) =>');
  if (!sync || !invalid.includes("m.code === 'reattach'") || !invalid.includes("sessionStorage.removeItem('" + sync[1] + "')")) throw new Error('Missing original seat credential lifecycle');
  return {rules: {queueCapacity: capacity}, fixtures: {roomCommandQueues: programs, roomReconnectOrder: recoveries}, inputs: ['public/js/net.js', 'public/js/main.js']};
}
