import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const read=path=>readFileSync(new URL('../'+path,import.meta.url));
const capture=JSON.parse(read('tests/fixtures/dialogue_layout.json'));
const campaign=JSON.parse(read('data/campaign.json'));
const provenance=JSON.parse(read('data/provenance.json'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');

test('source identities and native avatar/portrait bytes retain the captured inputs',()=>{
  assert.equal(capture.formatVersion,1);
  assert.equal(capture.host.language,'zh-Hant');
  for(const [path,hash]of Object.entries(capture.source.inputs))assert.equal(digest(read(path).toString('utf8').replace(/\r\n?/g,'\n')),hash,path);
  for(const [path,hash]of Object.entries(capture.source.sourceInputs))assert.equal(provenance.inputs[path],hash,path);
  assert.ok(Object.keys(capture.source.assetInputs).length>0);
  for(const [path,hash]of Object.entries(capture.source.assetInputs))assert.equal(digest(read(path.replace(/^public\//,''))),hash,path);
});

test('every authored settlement has character/mech references on both sides of the responsive boundary',()=>{
  const expected=new Set();
  for(const chapter of Object.keys(campaign.talk))for(const side of ['STEEL','SWARM'])for(const mode of ['char','mech'])for(const width of [360,720,721,1440])expected.add(`${chapter}/${side}/${mode}/${width}`);
  for(const program of capture.programs){
    const key=`${program.chapter}/${program.side}/${program.artMode}/${program.viewport.width}`;
    assert.ok(expected.delete(key),'Missing, duplicated or unexpected profile: '+key);
    assert.deepEqual(program.scene,campaign.talk[program.chapter][program.side].base);
    assert.equal(program.state.rows.length,program.scene.lines.length);
    for(let index=0;index<program.scene.lines.length;index++)assert.equal(program.state.rows[index].line.value,program.scene.lines[index].t);
  }
  assert.equal(expected.size,0);
});

test('captured font usage and source layout distinguish typography and material requirements',()=>{
  assert.ok(capture.fonts.some(font=>new URL(font.url).hostname==='fonts.googleapis.com'));
  assert.ok(capture.fonts.some(font=>font.path.endsWith('.woff2')));
  for(const font of capture.fonts){assert.match(font.sha256,/^[a-f0-9]{64}$/);assert.ok(font.bytes>0);assert.ok(['fonts.googleapis.com','fonts.gstatic.com'].includes(new URL(font.url).hostname));}
  for(const program of capture.programs){
    assert.ok(program.fonts.line.some(font=>font.isCustomFont&&font.familyName.startsWith('Noto Sans TC')));
    const {script,portraits,rows}=program.state;
    assert.equal(script.style.paddingTop,'12px');assert.equal(script.style.paddingBottom,'12px');
    assert.equal(script.style.paddingLeft,'14px');assert.equal(script.style.paddingRight,'14px');assert.equal(script.style.gap,'9px');
    assert.equal(script.style.maxHeight,program.viewport.height*.42+'px');
    for(const portrait of portraits){
      assert.ok(portrait.decoded&&portrait.natural.every(value=>value>0));
      assert.equal(portrait.style.display,program.viewport.width<=720?'none':'block');
      assert.equal(portrait.style.opacity,'0.22');assert.equal(portrait.style.width,'150px');assert.match(portrait.style.maskImage,/linear-gradient\(to top,/);
    }
    for(const row of rows){
      assert.equal(row.style.opacity,'1');assert.equal(row.style.transform,'none');
      assert.equal(row.avatar.style.width,'40px');assert.equal(row.avatar.style.height,'40px');
      assert.equal(row.line.style.fontSize,'14px');assert.equal(row.speaker.style.fontSize,'12px');
      assert.equal(row.text.style.textAlign,row.style.flexDirection==='row-reverse'?'right':'left');
    }
  }
});

test('all source screenshots have sealed PNG bytes matching the measured component dimensions',()=>{
  for(const program of capture.programs){
    const png=Buffer.from(program.image.png,'base64');assert.equal(digest(png),program.image.sha256);
    assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
    const width=png.readUInt32BE(16),height=png.readUInt32BE(20);
    const [x,y,w,h]=program.state.bounds;
    assert.equal(width,Math.ceil(x+w)-Math.floor(x));
    assert.equal(height,Math.ceil(y+h)-Math.floor(y));
  }
});
