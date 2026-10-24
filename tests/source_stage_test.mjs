import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFile,mkdir,mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import test from 'node:test';
import {publishSourceStage,publishReferenceSections} from '../tools/source_stage.mjs';
import {captureGenerator} from '../tools/source_provenance.mjs';

const project=resolve('.');
const input='scripts/source_rng.gd';
const sourceHash=createHash('sha256').update(await readFile(input)).digest('hex');
const currentProvenance=JSON.parse(await readFile('data/provenance.json','utf8'));

async function rejectedCapture() {
  await mkdir('artifacts/source-stage-tests',{recursive:true});
  const base=await mkdtemp(resolve('artifacts/source-stage-tests/case-'));
  const root=join(base,'destination'),stage=join(base,'capture');
  await mkdir(join(root,'data'),{recursive:true});
  await mkdir(join(stage,'data'),{recursive:true});
  await mkdir(join(root,'tests'),{recursive:true});
  await mkdir(join(root,'tools'),{recursive:true});
  await writeFile(join(root,'tools/generator.mjs'),'export const revision=1;');
  await writeFile(join(root,'data/fixtures.json'),'original publication');
  const provenance={runtime:'GDScript',producer:await captureGenerator(root),workspaceInputs:{},heroes:currentProvenance.heroes,qualifiedMaps:currentProvenance.qualifiedMaps,inputs:{[input]:sourceHash}};
  const save=()=>writeFile(join(stage,'data/provenance.json'),JSON.stringify(provenance));
  await save();
  return {root,stage,provenance,save,unchanged:async()=>assert.equal(await readFile(join(root,'data/fixtures.json'),'utf8'),'original publication')};
}

test('source path traversal cannot reach publication',async()=>{
  const fixture=await rejectedCapture();
  fixture.provenance.inputs={'../escaped.gd':sourceHash};await fixture.save();
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/leaves its root/);
  await fixture.unchanged();
});

test('stale source bytes cannot overwrite the current publication',async()=>{
  const fixture=await rejectedCapture();
  fixture.provenance.inputs[input]='0'.repeat(64);await fixture.save();
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/source input is stale/);
  await fixture.unchanged();
});

test('truncated captured JSON cannot overwrite the current publication',async()=>{
  const fixture=await rejectedCapture();
  for(const name of ['balance','maps'])await copyFile(join(project,'data',name+'.json'),join(fixture.stage,'data',name+'.json'));
  await writeFile(join(fixture.stage,'data/fixtures.json'),'{"rng":[');
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/Parser|parse|expected/i);
  await fixture.unchanged();
});

test('an omitted registered fixture prevents publication before any writes',async()=>{
  const fixture=await rejectedCapture();
  for(const name of ['balance','maps'])await copyFile(join(project,'data',name+'.json'),join(fixture.stage,'data',name+'.json'));
  await copyFile(join(project,'tests/room_recovery_suite.gd'),join(fixture.root,'tests/room_recovery_suite.gd'));
  await writeFile(join(fixture.stage,'data/fixtures.json'),'{"rng":[],"volumes":[],"shield":[]}');
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/lacks registered fixture sections: roomCommandQueues, roomReconnectOrder/);
  await fixture.unchanged();
});

test('unguarded native fixture reads are required without treating methods or file paths as sections',async()=>{
  const fixture=await rejectedCapture();
  for(const name of ['balance','maps'])await copyFile(join(project,'data',name+'.json'),join(fixture.stage,'data',name+'.json'));
  await writeFile(join(fixture.root,'tests/run.gd'),'var path="res://data/fixtures.json"\nfunc run(fixtures):\n\tfixtures.filter(func(row):return row)\n\tfor row in fixtures.requiredFrames:\n\t\tpass\n');
  await writeFile(join(fixture.stage,'data/fixtures.json'),'{"rng":[],"volumes":[],"shield":[]}');
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/lacks registered fixture sections: requiredFrames$/);
  await fixture.unchanged();
});

test('focused references reject stale source inputs before executing the producer',async()=>{
  const fixture=await rejectedCapture();
  fixture.provenance.inputs[input]='0'.repeat(64);
  await writeFile(join(fixture.root,'data/provenance.json'),JSON.stringify(fixture.provenance));
  let called=false;
  await assert.rejects(publishReferenceSections(fixture.root,project,async()=>{called=true;return {};}),/Published source input is stale/);
  assert.equal(called,false);
  await fixture.unchanged();
});

test('focused references cannot overwrite a publication changed during capture',async()=>{
  const fixture=await rejectedCapture();
  await writeFile(join(fixture.root,'data/provenance.json'),JSON.stringify(fixture.provenance));
  await assert.rejects(publishReferenceSections(fixture.root,project,async()=>{
    await writeFile(join(fixture.root,'data/fixtures.json'),'newer publication');return {rng:[]};
  }),/Source publication changed during focused reference capture/);
  assert.equal(await readFile(join(fixture.root,'data/fixtures.json'),'utf8'),'newer publication');
});

test('an older migration generator capture is rejected before destination writes',async()=>{
  const fixture=await rejectedCapture();
  await writeFile(join(fixture.root,'tools/generator.mjs'),'export const revision=2;');
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/generator revision is stale/);
  await fixture.unchanged();
});

test('an unsealed capture cannot be promoted using the current generator identity',async()=>{
  const fixture=await rejectedCapture();
  delete fixture.provenance.producer;await fixture.save();
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/Missing source capture generator identity/);
  await fixture.unchanged();
});

test('a generator edit during focused capture cannot publish mixed reference versions',async()=>{
  const fixture=await rejectedCapture();
  await writeFile(join(fixture.root,'data/provenance.json'),JSON.stringify(fixture.provenance));
  await assert.rejects(publishReferenceSections(fixture.root,project,async()=>{
    await writeFile(join(fixture.root,'tools/generator.mjs'),'export const revision=2;');return {rng:[]};
  }),/generator revision is stale/);
  await fixture.unchanged();
});

test('source editor import descriptors cannot overwrite native resource metadata',async()=>{
  const fixture=await rejectedCapture();
  for(const name of ['balance','maps'])await copyFile(join(project,'data',name+'.json'),join(fixture.stage,'data',name+'.json'));
  await mkdir(join(fixture.stage,'assets'),{recursive:true});
  await writeFile(join(fixture.stage,'assets/texture.png.import'),'foreign source path');
  await writeFile(join(fixture.stage,'data/fixtures.json'),'{"rng":[],"volumes":[],"shield":[]}');
  await assert.rejects(publishSourceStage(fixture.root,project,fixture.stage),/Captured Godot import descriptor/);
  await fixture.unchanged();
});
