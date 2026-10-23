import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {selectWorldBundles} from '../tools/world_selection.mjs';

const root = new URL('../data/', import.meta.url);
const maps = JSON.parse(await readFile(new URL('maps.json', root), 'utf8'));
const campaign = JSON.parse(await readFile(new URL('campaign.json', root), 'utf8'));
const balance = JSON.parse(await readFile(new URL('balance.json', root), 'utf8'));
const seasons = Object.keys(balance.constants.ENV.seasons);
const catalog = [...maps, ...campaign.maps];

test('complete source manifest preserves every authored layout/team/season configuration', () => {
  const selected = selectWorldBundles(catalog, seasons);
  let count = 0;
  for (const entry of catalog) {
    for (const [suffix, variants] of [['', entry.variants], ...(entry.swapped_variants ? [['_swap', entry.swapped_variants]] : [])]) {
      for (const size of Object.keys(variants)) {
        const authored = entry.chapter ? [variants[size].config.env?.season || 'summer'] : seasons;
        for (const season of authored) {
          const bundle = selected.get(`${entry.id}${suffix}_${size}_${season}`);
          assert.ok(bundle);
          assert.equal(bundle.size, Number(size));
          assert.equal(bundle.season, season);
          assert.equal(bundle.map.variants[size], variants[size]);
          count++;
        }
      }
    }
  }
  assert.equal(selected.size, count);
});

test('incremental selection cannot capture other teams, seasons, or base assignments', () => {
  const selected = selectWorldBundles(catalog, seasons, ['--reuse', '--bundle=berlin_1_spring']);
  assert.deepEqual([...selected.keys()], ['berlin_1_spring']);
  const swap = selectWorldBundles(catalog, seasons, ['berlin_swap', '--bundle=berlin_swap_1_spring']);
  assert.deepEqual([...swap.keys()], ['berlin_swap_1_spring']);
  const both = selectWorldBundles(catalog, seasons, ['berlin', '--list-bundles']);
  assert.ok(both.has('berlin_1_spring') && both.has('berlin_swap_1_spring'));
  assert.ok([...both.values()].every(value => value.map.id === 'berlin' || value.map.id === 'berlin_swap'));
});

test('invalid, conflicting and traversal-like bundle selectors fail before capture', () => {
  for (const args of [['missing'], ['--bad'], ['--bundle='], ['--bundle=../berlin_1_spring'],
    ['madrid', '--bundle=berlin_1_spring'], ['--bundle=berlin_6_spring'], ['--bundle=berlin_1_invalid']]) {
    assert.throws(() => selectWorldBundles(catalog, seasons, args));
  }
  assert.deepEqual([...selectWorldBundles(catalog, seasons, ['--bundle=berlin_1_spring', '--bundle=berlin_1_spring']).keys()],
    ['berlin_1_spring']);
});
