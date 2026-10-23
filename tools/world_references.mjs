import { readFile, readdir } from 'node:fs/promises';
import {writeSourceFile} from './fixture_json.mjs';
import { resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const source = resolve(process.env.SVS_SOURCE || join(root, '..', 'steel_vs_swarm'));
const {readSrc,grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const sourceText=readSrc('public','js','biomes.js');
const makeIndex=new Function(`${grabFn(sourceText,'makeDeckIndex')}\nreturn makeDeckIndex;`)();
const tolerance=/const LONG_TOL = ([\d.]+)/.exec(grabFn(sourceText,'makeDeckIndex'));
if(!tolerance)throw new Error('Original deck endpoint tolerance missing');
const selected=process.argv.slice(2);
for(const file of await readdir(join(root,'data/worlds'))){
  if(!file.endsWith('.json') || (selected.length&&!selected.some(id=>file===id+'.json'||file.startsWith(id+'_'))))continue;
  const path=join(root,'data/worlds',file);
  const data=JSON.parse(await readFile(path,'utf8'));
  const query=makeIndex(data.decks);
  data.collision.deckEndTolerance=Number(tolerance[1]);
  data.deckProbes=data.decks.filter(d=>Math.hypot(d.x2-d.x1,d.z2-d.z1)>0).map(d=>{
    const dx=d.x2-d.x1,dz=d.z2-d.z1,length=Math.hypot(dx,dz);
    const x=Math.fround(d.x1+dx*.371+dz/length*d.hw*.173);
    const z=Math.fround(d.z1+dz*.371-dx/length*d.hw*.173);
    const y=d.y1+(d.y2-d.y1)*.371;
    return{x,z,y,upper:query(x,z,0,y-.03,y+.03),
      lower:query(x,z,0,y-.03,y+.03,true)-data.collision.deckThickness};
  });
  await writeSourceFile(path,JSON.stringify(data));
}
console.log('Source layered-deck query references generated');
