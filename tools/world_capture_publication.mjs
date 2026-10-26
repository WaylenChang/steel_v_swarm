import {verifyWorldProvenance} from './world_provenance.mjs';
import {prepareSourceJson} from './source_json.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

// Long captures can outlive edits to the original working tree. Keep the last
// manifest intact unless its declared input and asset bytes still qualify.
export async function publishWorldCapture(path,world,sourceDirectory) {
  await verifyWorldProvenance(world,sourceDirectory);
  await writeFixtureJson(path,prepareSourceJson(world));
}
