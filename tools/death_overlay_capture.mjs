import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {captureDeathOverlay,captureDeathOverlayRasters} from './death_overlay_references.mjs';
import {captureDeathSequences} from './death_sequence_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const name='public/css/style.css';
const css=await readFile(join(source,name));
const hash=digest(css);
if(provenance.inputs?.[name]!==hash)throw new Error('Source CSS changed; refresh shared source metadata first');
const sourceInputs={[name]:hash};
for(const file of ['public/js/game.js','public/js/data.js','public/js/botPolicy.js','public/js/balancePrefs.js',
  'public/js/rng.js','out/forest_review/three.module.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,file));
  if(provenance.inputs?.[file]!==digest(bytes))throw new Error('Source input changed; refresh shared source metadata first: '+file);
  sourceInputs[file]=digest(bytes);
}
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const prototype={};
for(const method of ['_onSelfDeath','_updateDeathSeq','_onSelfRespawn'])
  prototype[method]=new Function('return ({'+grabMethod(game,method)+'});')()[method];
const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
const d=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const sequences=captureDeathSequences({THREE,d,BattleClient:{prototype}});
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Death overlay capture requires the original development Playwright runtime');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage();
  const captured=await page.evaluate(({capture,css})=>new Function('return ('+capture+');')()({css}),
    {capture:captureDeathOverlay.toString(),css:css.toString()});
  captured.fixtures.deathOverlayRasters=await captureDeathOverlayRasters(page,css.toString());
  Object.assign(captured.fixtures,sequences);
  for(const [file,expected]of Object.entries(sourceInputs))
    if(digest(await readFile(join(source,file)))!==expected)throw new Error('Source changed during death presentation capture: '+file);
  const inputs={};
  for(const file of ['tools/death_overlay_capture.mjs','tools/death_overlay_references.mjs','tools/death_sequence_references.mjs'])
    inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/death_overlay.json'),{formatVersion:1,
    source:{inputs,sourceInputs},metadata:captured.rules,fixtures:captured.fixtures});
  console.log('DEATH_OVERLAY_REFERENCES_PASS '+JSON.stringify({opacity:captured.fixtures.deathOverlayOpacity.length,
    rasters:captured.fixtures.deathOverlayRasters.length,sequences:sequences.deathSequences.length}));
} finally {await browser.close();}
