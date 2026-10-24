import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureDestruction} from './destruction_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
async function original(name) {
  const bytes=await readFile(join(source,name));
  const hash=digest(bytes);
  if(provenance.inputs?.[name]!==hash)throw new Error('Source input changed; refresh shared source metadata first: '+name);
  sourceInputs[name]=hash;
  return bytes;
}
const game=(await original('public/js/game.js')).toString().replace(/\r\n?/g,'\n');
const vfx=(await original('public/js/vfx.js')).toString().replace(/\r\n?/g,'\n');
const crowdedLine=vfx.slice(vfx.indexOf('const crowded =')).split('\n')[0];
const caps=/lowPower\(\) \? (\d+) : (\d+)/.exec(crowdedLine);
const maximum=/const FX_MAX = (\d+);/.exec(game);
if(!caps||!maximum)throw new Error('Missing original destruction effect budgets');
const limits={low:Number(caps[1]),normal:Number(caps[2]),maximum:Number(maximum[1])};
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Destruction capture requires the original development Playwright runtime');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage();
  const origin='http://godot-destruction.invalid';
  const routeErrors=[];
  await page.route('**/*',async route=>{
    try {
      const url=new URL(route.request().url());
      if(url.origin===origin&&url.pathname==='/')return await route.fulfill({contentType:'text/html',body:
        '<script type="importmap">{"imports":{"three":"https://unpkg.com/three@0.160.0/build/three.module.js","three/addons/":"https://unpkg.com/three@0.160.0/examples/jsm/"}}</script>'});
      let name;
      if(url.pathname.endsWith('/build/three.module.js'))name='out/forest_review/three.module.js';
      else if(/\/examples\/jsm\/(.*\.js)$/.test(url.pathname))
        name='out/forest_review/'+/\/examples\/jsm\/(.*\.js)$/.exec(url.pathname)[1].replaceAll('/','_');
      else if(url.origin===origin&&/^\/js\/[\w/.-]+\.js$/.test(url.pathname)&&!url.pathname.includes('..'))name='public'+url.pathname;
      else throw new Error('Uncaptured destruction dependency: '+url.href);
      await route.fulfill({contentType:'text/javascript',body:await original(name)});
    } catch(error) {routeErrors.push(error.message);await route.abort();}
  });
  await page.goto(origin);
  const result=await page.evaluate(async ({capture,limits})=>{
    const THREE=await import('three');
    const d=await import('/js/data.js');
    const fx=await import('/js/vfx.js');
    const sceneDamage=await import('/js/sceneDamage.js');
    const {BattleClient}=await import('/js/game.js');
    const {setLowPower}=await import('/js/mobile.js');
    const {disposeTree}=await import('/js/toon.js');
    const run=new Function('return ('+capture+');')();
    // Native Three.js serialization retains real geometry; this fixture publishes only particle state.
    const captured=run({THREE,d,fx,sceneDamage,BattleClient,setLowPower,limits,disposeTree,
      graphOf:mesh=>({data:mesh.toJSON()})});
    const {palette,comicKeys,sizes,lifetimes}=captured.rules;
    const {mechanicalDebris,comicPops}=captured.fixtures;
    return {metadata:{palette,comicKeys,sizes,lifetimes},fixtures:{mechanicalDebris,comicPops},textures:captured.textures};
  },{capture:captureDestruction.toString(),limits}).catch(error=>{
    throw new Error([...routeErrors,error.message].join('\n'),{cause:error});
  });
  if(routeErrors.length)throw new Error(routeErrors.join('\n'));
  for(const [name,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,name)))!==expected)throw new Error('Source changed during destruction capture: '+name);
  const inputs={};
  for(const name of ['tools/destruction_capture.mjs','tools/destruction_references.mjs'])
    inputs[name]=digest((await readFile(join(root,name),'utf8')).replace(/\r\n?/g,'\n'));
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/destruction.json'),{formatVersion:1,source:{inputs,sourceInputs},...result});
  console.log('DESTRUCTION_REFERENCES_PASS '+JSON.stringify(Object.fromEntries(Object.entries(result.fixtures)
    .map(([key,value])=>[key,value.length]))));
} finally {await browser.close();}
