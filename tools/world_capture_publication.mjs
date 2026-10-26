import {verifyWorldProvenance} from './world_provenance.mjs';
import {prepareSourceJson} from './source_json.mjs';
import {writeFixtureJson} from './fixture_json.mjs';
import {dirname} from 'node:path';
import {verifyWorldStorage} from './world_source.mjs';

// Long captures can outlive edits to the original working tree. Keep the last
// manifest intact unless its stored dependencies and original bytes still qualify.
export async function publishWorldCapture(path,world,sourceDirectory) {
  await verifyWorldStorage(world,dirname(path));
  await verifyWorldProvenance(world,sourceDirectory);
  await writeFixtureJson(path,prepareSourceJson(world));
}
