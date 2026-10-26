import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readWorldHeader} from './world_source.mjs';
import {selectWorldBundles} from './world_selection.mjs';
import {verifyWorldProvenance} from './world_provenance.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const [bundle,...extra]=process.argv.slice(2);
if(typeof bundle!=='string'||!/^[a-zA-Z0-9_]+$/.test(bundle)||extra.length)
  throw new Error('Select exactly one original source world bundle');
const read=async name=>JSON.parse(await readFile(join(root,'data',name),'utf8'));
const [maps,campaign,balance]=await Promise.all([read('maps.json'),read('campaign.json'),read('balance.json')]);
const selected=selectWorldBundles([...maps,...campaign.maps],Object.keys(balance.constants.ENV.seasons),['--bundle='+bundle]);
const expected=selected.get(bundle),world=await readWorldHeader(join(root,'data/worlds',bundle+'.json'));
const identity=world.source?.identity;
if(!identity||Object.keys(identity).length!==3||identity.map!==expected.map.id||identity.teamSize!==expected.size||identity.season!==expected.season)
  throw new Error('Original world provenance identity does not match its selected bundle: '+bundle);
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const result=await verifyWorldProvenance(world,source);
console.log('WORLD_SOURCE_PROVENANCE_PASS '+JSON.stringify({bundle,...result}));
