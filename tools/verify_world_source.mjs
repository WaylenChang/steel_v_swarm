import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readWorldHeader,verifyWorldStorage} from './world_source.mjs';
import {selectWorldBundles} from './world_selection.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const [bundle,...extra]=process.argv.slice(2);
if(typeof bundle!=='string'||!/^[a-zA-Z0-9_]+$/.test(bundle)||extra.length)
  throw new Error('Select exactly one original source world bundle');
const read=async name=>JSON.parse(await readFile(join(root,'data',name),'utf8'));
const [maps,campaign,balance]=await Promise.all([read('maps.json'),read('campaign.json'),read('balance.json')]);
const selected=selectWorldBundles([...maps,...campaign.maps],Object.keys(balance.constants.ENV.seasons),['--bundle='+bundle]);
const expected=selected.get(bundle),directory=join(root,'data/worlds');
const world=await readWorldHeader(join(directory,bundle+'.json'));
const identity=world.source?.identity;
if(!identity||Object.keys(identity).length!==3||identity.map!==expected.map.id
  ||identity.teamSize!==expected.size||identity.season!==expected.season)
  throw new Error('Source world identity does not match its selected bundle: '+bundle);
const result=await verifyWorldStorage(world,directory);
console.log('WORLD_SOURCE_STORAGE_PASS '+JSON.stringify({bundle,...result}));
