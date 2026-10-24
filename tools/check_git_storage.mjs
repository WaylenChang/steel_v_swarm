import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {stat} from 'node:fs/promises';
import {isAbsolute, relative, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

export const MAX_GIT_BLOB_BYTES = 100 * 1024 * 1024;

function git(root, args, input) {
  const result = spawnSync('git', ['-C', root, ...args], {
    input, encoding: 'utf8', maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr.trim() || 'Git storage inspection failed');
  return result.stdout;
}

function entries(root, ref) {
  if (ref) {
    const tree = git(root, ['rev-parse', '--verify', '--end-of-options', ref + '^{tree}']).trim();
    return git(root, ['ls-tree', '-r', '-z', '--full-tree', tree]).split('\0').filter(Boolean).flatMap(row => {
      const match = /^(\d+) (\w+) ([a-f0-9]+)\t([\s\S]+)$/.exec(row);
      if (!match) throw new Error('Invalid Git tree record');
      return match[2] === 'blob' ? [{oid: match[3], path: match[4]}] : [];
    });
  }
  return git(root, ['ls-files', '--stage', '-z']).split('\0').filter(Boolean).map(row => {
    const match = /^\d+ ([a-f0-9]+) (\d+)\t([\s\S]+)$/.exec(row);
    if (!match || match[2] !== '0') throw new Error('Resolve the unmerged index before checking storage');
    return {oid: match[1], path: match[3]};
  });
}

function pointer(text) {
  const match = /^version https:\/\/git-lfs.github.com\/spec\/v1\noid sha256:([a-f0-9]{64})\nsize (\d+)\n$/.exec(text);
  if (!match || !Number.isSafeInteger(Number(match[2]))) return null;
  return {sha256: match[1], bytes: Number(match[2])};
}

function child(root, name) {
  if (typeof name !== 'string' || name.includes('\\') || isAbsolute(name)) throw new Error('Invalid pinned path');
  const path = resolve(root, name), local = relative(root, path);
  if (!local || local === '..' || local.startsWith('../') || local.startsWith('..\\') || isAbsolute(local))
    throw new Error('Pinned path leaves the repository: ' + name);
  return path;
}

export async function checkGitStorage({root = process.cwd(), ref = null, verifyFixtures = false} = {}) {
  root = resolve(root);
  const records = entries(root, ref), byPath = new Map(records.map(row => [row.path, row]));
  const objects = new Map();
  const ids = [...new Set(records.map(row => row.oid))];
  if (ids.length) {
    for (const line of git(root, ['cat-file', '--batch-check=%(objectname) %(objecttype) %(objectsize)'], ids.join('\n') + '\n').trim().split('\n')) {
      const match = /^([a-f0-9]+) blob (\d+)$/.exec(line);
      if (!match) throw new Error('Missing or invalid indexed Git object: ' + line);
      objects.set(match[1], Number(match[2]));
    }
  }
  const filters = new Map();
  if (records.length) {
    const args = ['check-attr', ref ? '--source=' + ref : '--cached', '-z', '--stdin', 'filter'];
    const attributes = git(root, args, records.map(row => row.path).join('\0') + '\0').split('\0');
    for (let index = 0; index + 2 < attributes.length; index += 3) filters.set(attributes[index], attributes[index + 2]);
  }
  const errors = [], pointers = new Map();
  let largestBlob = 0, lfsFiles = 0;
  for (const row of records) {
    const bytes = objects.get(row.oid);
    largestBlob = Math.max(largestBlob, bytes);
    if (bytes > MAX_GIT_BLOB_BYTES) errors.push(row.path + ': regular Git blob exceeds 100 MiB; track it with Git LFS before committing');
    if (filters.get(row.path) === 'lfs') {
      const value = bytes <= 1024 ? pointer(git(root, ['cat-file', 'blob', row.oid])) : null;
      if (!value) errors.push(row.path + ': LFS attribute is set but the index contains raw data instead of a canonical pointer');
      else { pointers.set(row.path, value); lfsFiles++; }
    }
  }
  if (errors.length) throw new Error(errors.join('\n'));

  let pinnedFiles = 0, fixtureSections = 0;
  if (verifyFixtures && byPath.has('data/fixtures.json')) {
    const manifest = JSON.parse(git(root, ['cat-file', 'blob', byPath.get('data/fixtures.json').oid]));
    if (manifest.fixtureFormat === 'source-sections-v1') {
      const pinned = new Map();
      const add = (name, expected) => {
        if (pinned.has(name) && JSON.stringify(pinned.get(name)) !== JSON.stringify(expected))
          throw new Error('Conflicting pinned descriptors: ' + name);
        pinned.set(name, expected);
      };
      for (const section of Object.values(manifest.sections)) {
        fixtureSections++;
        for (const part of section.parts) {
          for (const value of [part, part.numbers].filter(Boolean)) {
            if (!value.path.startsWith('fixture_parts/')) throw new Error('Invalid source fixture part path');
            add('data/' + value.path, {sha256: value.sha256, bytes: value.bytes});
          }
        }
      }
      for (const [name, value] of Object.entries(manifest.consumers)) add(name, {sha256: value.sha256});
      const objectFormat = git(root, ['rev-parse', '--show-object-format']).trim();
      for (const [name, expected] of pinned) {
        const row = byPath.get(name);
        if (!row) throw new Error('Pinned input is missing from the commit: ' + name);
        const path = child(root, name), info = await stat(path);
        if (!info.isFile() || expected.bytes !== undefined && info.size !== expected.bytes)
          throw new Error('Pinned input has changed size: ' + name);
        const content = createHash('sha256'), blob = createHash(objectFormat).update('blob ' + info.size + '\0');
        for await (const bytes of createReadStream(path)) { content.update(bytes); blob.update(bytes); }
        const sha256 = content.digest('hex');
        if (sha256 !== expected.sha256) throw new Error('Pinned input differs from the captured bytes: ' + name);
        const lfs = pointers.get(name);
        if (lfs ? lfs.sha256 !== sha256 || lfs.bytes !== info.size : blob.digest('hex') !== row.oid)
          throw new Error('Git changed or staged different pinned bytes; disable text conversion for: ' + name);
        pinnedFiles++;
      }
    }
  }
  return {files: records.length, largestBlob, lfsFiles, fixtureSections, pinnedFiles};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = process.argv.slice(2), options = {};
  try {
    for (let index = 0; index < args.length; index++) {
      if (args[index] === '--staged') continue;
      if (args[index] === '--verify-fixtures') options.verifyFixtures = true;
      else if (args[index] === '--ref' && args[index + 1]) options.ref = args[++index];
      else throw new Error('Usage: node tools/check_git_storage.mjs [--staged | --ref REV] [--verify-fixtures]');
    }
    console.log('GIT_STORAGE_PASS ' + JSON.stringify(await checkGitStorage(options)));
  } catch (error) {
    console.error('GIT_STORAGE_FAIL ' + error.message);
    process.exitCode = 1;
  }
}
