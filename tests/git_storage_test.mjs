import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, truncate, writeFile} from 'node:fs/promises';
import {join, resolve, sep} from 'node:path';
import test from 'node:test';
import {checkGitStorage, MAX_GIT_BLOB_BYTES} from '../tools/check_git_storage.mjs';

const base = resolve('artifacts/git-storage/tests');
const policy = await readFile(new URL('../.gitattributes', import.meta.url));
await mkdir(base, {recursive: true});

function git(root, ...args) {
  // LFS pointer cases deliberately stage raw bytes; the checker must detect
  // bypassed filters even when no LFS client is installed on the test host.
  const result = spawnSync('git', ['-C', root, '-c', 'core.autocrlf=true',
    '-c', 'filter.lfs.process=', '-c', 'filter.lfs.clean=', '-c', 'filter.lfs.smudge=',
    '-c', 'filter.lfs.required=false', ...args], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return result.stdout.trim();
}

async function repository(t, attributes = policy) {
  const root = await mkdtemp(join(base, 'case-'));
  t.after(async () => {
    const target = resolve(root);
    if (!target.startsWith(base + sep)) throw new Error('Test cleanup leaves its workspace');
    await rm(target, {recursive: true, force: true});
  });
  git(root, 'init', '--quiet');
  await writeFile(join(root, '.gitattributes'), attributes);
  return root;
}

async function pinnedInputs(root) {
  await mkdir(join(root, 'data/fixture_parts'), {recursive: true});
  await mkdir(join(root, 'tests'), {recursive: true});
  const data = Buffer.from('[\r\n{"value":-0,"unicode":"鋼"}\n]\r\n');
  const numbers = Buffer.alloc(8); numbers.writeDoubleLE(-0);
  const consumer = Buffer.from('extends Node\r\n# Pinned mixed endings.\n');
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  await writeFile(join(root, 'data/fixture_parts/case.json'), data);
  await writeFile(join(root, 'data/fixture_parts/numbers.f64'), numbers);
  await writeFile(join(root, 'tests/pinned.gd'), consumer);
  const manifest = {fixtureFormat: 'source-sections-v1', sections: {example: {parts: [{
    path: 'fixture_parts/case.json', bytes: data.length, sha256: hash(data),
    numbers: {path: 'fixture_parts/numbers.f64', bytes: numbers.length, sha256: hash(numbers)},
  }]}}, consumers: {'tests/pinned.gd': {sha256: hash(consumer)}}};
  await writeFile(join(root, 'data/fixtures.json'), JSON.stringify(manifest));
}

test('Windows staging and committed-tree reads preserve fixture bytes and pinned source endings', async t => {
  const root = await repository(t);
  await pinnedInputs(root);
  git(root, 'add', '--all');
  const staged = await checkGitStorage({root, verifyFixtures: true});
  assert.equal(staged.fixtureSections, 1);
  assert.equal(staged.pinnedFiles, 3);
  const tree = git(root, 'write-tree');
  await writeFile(join(root, '.gitattributes'), '* text=auto\n');
  assert.equal((await checkGitStorage({root, ref: tree, verifyFixtures: true})).pinnedFiles, 3);
});

test('an index containing normalized pinned bytes is rejected before commit', async t => {
  const root = await repository(t, '* text=auto\n');
  await pinnedInputs(root);
  git(root, 'add', '--all');
  await assert.rejects(checkGitStorage({root, verifyFixtures: true}), /Git changed or staged different pinned bytes/);
});

test('all referenced fixture files must be present in the staged tree', async t => {
  const root = await repository(t);
  await pinnedInputs(root);
  git(root, 'add', '--all');
  git(root, 'rm', '--cached', '--', 'data/fixture_parts/numbers.f64');
  await assert.rejects(checkGitStorage({root, verifyFixtures: true}), /Pinned input is missing from the commit/);
});

test('LFS declarations cannot hide raw staged data, and canonical pointers remain accepted', async t => {
  const root = await repository(t, '*.payload filter=lfs -text\n');
  await writeFile(join(root, 'large.payload'), 'raw');
  git(root, 'add', '--all');
  await assert.rejects(checkGitStorage({root}), /index contains raw data/);
  await writeFile(join(root, 'large.payload'), 'version https://git-lfs.github.com/spec/v1\noid sha256:' + 'a'.repeat(64) + '\nsize 200000000\n');
  git(root, 'add', '--all');
  assert.equal((await checkGitStorage({root})).lfsFiles, 1);
});

test('an actual regular Git blob above the GitHub limit is rejected', async t => {
  const root = await repository(t);
  const path = join(root, 'oversized.bin');
  await writeFile(path, Buffer.alloc(1));
  await truncate(path, MAX_GIT_BLOB_BYTES + 1);
  git(root, 'add', '--all');
  await assert.rejects(checkGitStorage({root}), /regular Git blob exceeds 100 MiB/);
});
