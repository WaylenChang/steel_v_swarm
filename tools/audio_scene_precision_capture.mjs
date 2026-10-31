import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {audioScenePrecisionPrograms,runAudioScenePrecision,sceneNumericPart} from './audio_scene_precision_references.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/game.js','public/js/data.js','tools/audit_src.mjs']) {
  const bytes=await readFile(join(source,path));
  assert.equal(hash(bytes),provenance.inputs[path],'Original audio scene input: '+path);
  sourceInputs[path]=hash(bytes);
}
const {grabMethod,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const text=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const data=(await readFile(join(source,'public/js/data.js'),'utf8')).replace(/\r\n?/g,'\n');
const roster=new Function(grabConst(data,'CHARACTERS')+';return CHARACTERS;')();
const characters=Object.fromEntries(Object.entries(roster).map(([id,value])=>
  [id,{visual:value.visual?.flight===undefined?{}:{flight:value.visual.flight}}]));
const methods=Object.fromEntries(['_moveCat','_entWeights','_updateMoveAudio','_updatePlaceAudio','_ambDensityAt']
  .map(name=>[name,grabMethod(text,name)]));
const cell=Number(/const C = ([\d.]+)/.exec(grabMethod(text,'_buildBlockGrid'))?.[1]);
assert.ok(Number.isFinite(cell)&&cell>0,'Original collision-grid cell size');
const programs=audioScenePrecisionPrograms(characters);
const expected=runAudioScenePrecision(methods,programs,cell,characters,sceneNumericPart);
const producers=['tools/audio_scene_precision_capture.mjs','tools/audio_scene_precision_references.mjs',
  'tools/source_numeric_transfer.mjs','tools/fixture_json.mjs'];
const inputs=Object.fromEntries(await Promise.all(producers.map(async path=>
  [path,hash((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'))])));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Audio scene precision requires the original Chromium runtime');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const actual=await (await browser.newPage()).evaluate(({methods,programs,cell,characters,run,encode})=>
    new Function('return ('+run+');')()(methods,programs,cell,characters,new Function('return ('+encode+');')()),
    {methods,programs,cell,characters,run:runAudioScenePrecision.toString(),encode:sceneNumericPart.toString()});
  assert.deepEqual(actual,expected,'Original Node/Chromium source scene outputs retain every double word');
  for(const [path,digest]of Object.entries(sourceInputs))
    assert.equal(hash(await readFile(join(source,path))),digest,'Original input changed during capture: '+path);
  for(const [path,digest]of Object.entries(inputs))
    assert.equal(hash((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),digest,'Producer changed during capture: '+path);
  // Input words use the same offline Float64 transport as source AudioParams.
  for(const program of programs.movement) {
    if(Array.isArray(program.camera.position)) {
      program.camera.position=sceneNumericPart(program.camera.position);
      program.camera.right=sceneNumericPart(program.camera.right);
    }
    if(program.ownWeights)program.ownWeights=sceneNumericPart([program.ownWeights.walk,program.ownWeights.run]);
  }
  for(const program of [...programs.movement,...programs.places])for(const entity of program.entities) {
    // Programs can share an entity array; encode each source record only once.
    if(entity.mesh.position.encoding)continue;
    entity.mesh.position=sceneNumericPart(['x','y','z'].map(axis=>entity.mesh.position[axis]));
    if(entity.loco)entity.loco.w=sceneNumericPart([entity.loco.w.walk,entity.loco.w.run,entity.loco.w.air]);
  }
  programs.positions=programs.positions.map(sceneNumericPart);
  for(const program of programs.places)program.position=sceneNumericPart(program.position);
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/audio_scene_precision.json'),{
    formatVersion:1,scope:'original-audio-scene-precision',source:{inputs,sourceInputs,
      chromiumVersion:browser.version()},cell,characters,programs,expected:actual});
  console.log('AUDIO_SCENE_PRECISION_CAPTURE_PASS '+JSON.stringify({movement:programs.movement.length,
    density:programs.positions.length,places:programs.places.length}));
} finally {await browser.close();}
