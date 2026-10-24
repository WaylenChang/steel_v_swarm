import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {minimapReferences} from './minimap_references.mjs';
import {captureMinimapFog} from './minimap_fog_capture.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const file of ['public/js/game.js','public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js',
  'public/js/rng.js','public/index.html','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const data=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const capture=await minimapReferences(source,data);
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage();
  capture.rules.context=await page.evaluate(()=>{
    const context=document.createElement('canvas').getContext('2d');
    return {miterLimit:context.miterLimit,lineCap:context.lineCap,lineJoin:context.lineJoin};
  });
  capture.fixtures.minimapFog=await captureMinimapFog(page,
    ['_drawMinimap','_world2mm','_world2mmFull','_mmShadows','_buildBlockGrid','_blockersNear'].map(name=>grabMethod(game,name)),capture.rules.canvas);
  for(const [file,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during minimap capture: '+file);
  const inputs={};
  for(const file of ['tools/minimap_native_capture.mjs','tools/minimap_references.mjs','tools/minimap_marker_references.mjs',
    'tools/minimap_cadence_references.mjs','tools/minimap_lane_references.mjs','tools/minimap_vision_references.mjs','tools/minimap_fog_capture.mjs'])
    inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/minimap_native.json'),{formatVersion:1,
    source:{inputs,sourceInputs},browser:browser.version(),metadata:capture.rules,...capture.fixtures});
  console.log('MINIMAP_NATIVE_REFERENCES_PASS fogFrames='+capture.fixtures.minimapFog.frames.length);
} finally {await browser.close();}
