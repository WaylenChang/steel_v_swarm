import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureAquaticPointRasters} from './aquatic_references.mjs';
import {instrumentAquaticCapture} from './aquatic_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
async function original(file) {
  const bytes=await readFile(join(source,file)),hash=digest(bytes);
  if(provenance.inputs?.[file]!==hash)throw new Error('Refresh shared source metadata first: '+file);
  if(sourceInputs[file]&&sourceInputs[file]!==hash)throw new Error('Source changed between module requests: '+file);
  sourceInputs[file]=hash;return bytes;
}
await original('tools/audit_src.mjs');
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const aquatic=(await original('public/js/aquatics.js')).toString('utf8').replace(/\r\n?/g,'\n');
const factory=grabFn(instrumentAquaticCapture(aquatic,grabFn),'createSuspendedDetritus');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage(),errors=[],origin='http://godot-aquatic.invalid';
  // Fulfill source module imports locally; no app server or external CDN is used.
  await page.route('**/*',async route=>{
    const url=new URL(route.request().url());
    try {
      if(url.origin!==origin)return route.abort();
      if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:
        '<script type="importmap">{"imports":{"three":"/cached/three.module.js","three/addons/":"/cached/addons/"}}</script>'});
      let file;
      if(url.pathname==='/cached/three.module.js')file='out/forest_review/three.module.js';
      else if(url.pathname.startsWith('/cached/addons/'))file='out/forest_review/'+url.pathname.slice(15).replaceAll('/','_');
      else if(/^\/js\/[\w/-]+\.js$/.test(url.pathname))file='public'+url.pathname;
      else return route.abort();
      return await route.fulfill({contentType:'text/javascript',body:await original(file)});
    } catch(error) {errors.push(error.message);return route.abort();}
  });
  await page.goto(origin);
  const rasters=await captureAquaticPointRasters(page,factory);
  if(errors.length)throw new Error(errors.join('\n'));
  for(const [file,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during point capture: '+file);
  const inputs={};
  for(const file of ['tools/aquatic_point_capture.mjs','tools/aquatic_references.mjs','tools/aquatic_capture.mjs'])
    inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/aquatic_points.json'),{formatVersion:1,
    source:{inputs,sourceInputs},browser:browser.version(),fixtures:{aquaticPointRasters:rasters}});
  console.log('AQUATIC_POINT_REFERENCES_PASS cases='+rasters.length);
} finally {await browser.close();}
