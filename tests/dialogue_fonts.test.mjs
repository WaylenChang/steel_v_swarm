import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const read=path=>readFileSync(new URL('../'+path,import.meta.url));
const data=JSON.parse(read('data/dialogue_fonts.json'));
const capture=JSON.parse(read('tests/fixtures/dialogue_fonts.json'));
const campaign=JSON.parse(read('data/campaign.json'));
const layout=JSON.parse(read('tests/fixtures/dialogue_layout.json'));
const provenance=JSON.parse(read('data/provenance.json'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('native font manifest preserves the current captured source identity',()=>{
  assert.equal(data.formatVersion,1);assert.deepEqual(data.source,capture.source);
  assert.deepEqual(data.fonts,capture.fonts);assert.deepEqual(data.glyphs,capture.glyphs);assert.deepEqual(data.weights,[400,700]);
  assert.equal(data.source.language,layout.host.language);
  for(const [path,hash]of Object.entries(data.source.inputs))assert.equal(digest(read(path).toString('utf8').replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash]of Object.entries(data.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.ok(layout.fonts.some(font=>font.url===data.source.stylesheet.url&&font.sha256===data.source.stylesheet.sha256));
  assert.equal(digest(read('assets/fonts/dialogue-OFL.txt').toString('utf8').replace(/\r\n?/g,'\n')),data.source.licence.text_sha256);
});

test('frozen metrics cover every original radio and settlement text at its actual role sizes',()=>{
  const cases=new Set(capture.metrics.map(sample=>JSON.stringify([sample.text,sample.size,sample.weight])));
  for(const chapter of Object.values(campaign.talk))for(const side of Object.values(chapter))for(const scene of Object.values(side)){
    for(const size of [11,12]){assert.ok(cases.has(JSON.stringify([scene.title,size,700])));assert.ok(cases.has(JSON.stringify([scene.note,size,400])));}
    for(const line of scene.lines)for(const size of [13,14,15])assert.ok(cases.has(JSON.stringify([line.t,size,400])));
  }
  const glyphs=[...new Set(capture.metrics.flatMap(sample=>Array.from(sample.text).map(character=>character.codePointAt(0))))].sort((a,b)=>a-b);
  assert.deepEqual(data.glyphs,glyphs);
  for(const sample of capture.metrics){assert.ok(Number.isFinite(sample.width)&&sample.width>=0);assert.ok(sample.ink.every(Number.isFinite));}
});

test('pinned Unicode subsets have unique content identities and safe native cache names',()=>{
  assert.ok(data.fonts.length>0);
  assert.equal(new Set(data.fonts.map(font=>font.url)).size,data.fonts.length);
  for(const font of data.fonts){assert.match(font.sha256,/^[a-f0-9]{64}$/);assert.equal(font.path,font.sha256+'.woff2');assert.ok(font.bytes>0);assert.equal(new URL(font.url).hostname,'fonts.gstatic.com');}
});
