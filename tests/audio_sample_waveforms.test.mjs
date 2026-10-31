import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {decodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

const root=new URL('../',import.meta.url);
const profile=JSON.parse(await readFile(new URL('data/audio_sample_waveforms/48000.json',root),'utf8'));
const balance=JSON.parse(await readFile(new URL('data/balance.json',root),'utf8'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const controls=probe=>{
  const {bytes,rows,width,matrix}=decodeSourceNumericPart(probe.controls);
  assert.equal(rows,5);assert.equal(width,1);assert.equal(matrix,false);
  return Array.from({length:5},(_,index)=>bytes.readDoubleLE(index*8));
};
function channel(encoded,frames) {
  const bytes=Buffer.from(encoded,'base64');
  assert.equal(bytes.toString('base64'),encoded);
  assert.equal(bytes.length,frames*4);
  for(let offset=0;offset<bytes.length;offset+=4)assert.ok(Number.isFinite(bytes.readFloatLE(offset)));
  return bytes;
}

test('sample archive binds the complete original manifest, producers and matching context',async()=>{
  assert.equal(profile.formatVersion,1);
  assert.equal(profile.scope,'original-sample-context-waveforms');
  assert.equal(profile.sampleRate,48000);
  const provenance=JSON.parse(await readFile(new URL('data/provenance.json',root),'utf8'));
  assert.deepEqual(Object.keys(profile.source.sourceInputs).sort(),
    ['public/js/audio.js',...Object.values(balance.audio.samples).map(url=>'public/'+url)].sort());
  for(const [path,digest]of Object.entries(profile.source.sourceInputs))assert.equal(digest,provenance.inputs[path],path);
  assert.deepEqual(Object.keys(profile.source.inputs),
    ['tools/capture_audio_sample_waveforms.mjs','tools/source_numeric_transfer.mjs','tools/fixture_json.mjs']);
  for(const [path,digest]of Object.entries(profile.source.inputs))
    assert.equal(hash((await readFile(new URL(path,root),'utf8')).replace(/\r\n?/g,'\n')),digest,path);
  const parent=await readFile(new URL(profile.source.contextProfile.path,root));
  assert.equal(hash(parent),profile.source.contextProfile.sha256);
  const context=JSON.parse(parent);
  for(const key of ['audioSha256','chromiumVersion','jsFlags'])assert.equal(profile.source[key],context.source[key]);
  assert.equal(context.sampleRate,profile.sampleRate);
  assert.deepEqual(profile.samples.map(sample=>sample.id),Object.keys(balance.audio.samples));
  for(const sample of profile.samples) {
    assert.equal(sample.index,0);assert.equal(sample.url,balance.audio.samples[sample.id]);
    assert.equal(sample.sha256,provenance.inputs['public/'+sample.url]);
    assert.equal(sample.sampleRate,profile.sampleRate);
    assert.ok(Number.isSafeInteger(sample.frames)&&sample.frames>0);
    assert.equal(sample.channels.length,2);
    sample.channels.forEach(encoded=>channel(encoded,sample.frames));
  }
});

test('original loader preserves take order, codec failure and low-power registration',()=>{
  assert.deepEqual(profile.loader.map(value=>value.mode),['normal','missing','decode','low']);
  for(const value of profile.loader) {
    assert.equal(value.bgmCalls,1,'BGM callback transport is recorded; BGM playback is outside this capture');
    assert.deepEqual(value.requests,value.mode==='low'?[]:Object.values(balance.audio.samples));
    assert.equal(value.loaded,value.mode!=='low');
    assert.deepEqual(value.counts,value.mode==='normal'?Object.fromEntries(profile.samples.map(sample=>[sample.id,1])):{});
  }
});

test('all seven takes retain every random-rate/pan program and original reservation',()=>{
  assert.equal(profile.probes.length,63);
  for(const sample of profile.samples) {
    const probes=profile.probes.filter(probe=>probe.id===sample.id);
    assert.equal(probes.length,9);
    assert.deepEqual(probes.map(probe=>controls(probe).slice(1,3)),
      [0,.5,1-2**-32].flatMap(random=>[-.75,0,.75].map(pan=>[pan,random])));
    for(const probe of probes) {
      const [gain,,random,rate,reservation]=controls(probe);
      assert.equal(gain,.35);assert.equal(probe.take,0);
      const originalRate=1+(random*2-1)*balance.audio.rateJitter;
      assert.equal(rate,Math.fround(originalRate),'AudioParam stores Float32 independently of source budget');
      assert.equal(reservation,Math.min(sample.frames/profile.sampleRate/originalRate,2));
      assert.equal(probe.frames,Math.ceil(sample.frames/.9)+1024);
      assert.equal(probe.channels.length,2);
      probe.channels.forEach(encoded=>channel(encoded,probe.frames));
    }
  }
});

test('linear interpolation, last-frame extrapolation and Float32 gain reproduce the original exactly',()=>{
  for(const sample of profile.samples)for(const probe of profile.probes.filter(probe=>probe.id===sample.id&&controls(probe)[1]===0)) {
    const [gain,,,rate]=controls(probe);
    for(let side=0;side<2;side++) {
      const input=Buffer.from(sample.channels[side],'base64'),output=Buffer.from(probe.channels[side],'base64');
      let position=0,frame=0;
      while(position<sample.frames) {
        const index=Math.floor(position),fraction=position-index,first=input.readFloatLE(index*4);
        const value=index===sample.frames-1&&index>0?
          first+(first-input.readFloatLE((index-1)*4))*fraction:
          (1-fraction)*first+fraction*input.readFloatLE(Math.min(index+1,sample.frames-1)*4);
        assert.equal(output.readFloatLE(frame*4),Math.fround(Math.fround(value)*Math.fround(gain)),sample.id+':'+rate+':'+frame);
        frame++;position+=rate;
      }
      for(;frame<probe.frames;frame++)assert.equal(output.readFloatLE(frame*4),0,'Exact source EOF silence');
    }
  }
});

test('ambiguous context selectors reject before source access or browser launch',async()=>{
  for(const args of [[],['0'],['7999'],['384001'],['48000.5'],['048000'],['48000','extra']])
    await assert.rejects(promisify(execFile)(process.execPath,[fileURLToPath(new URL('tools/capture_audio_sample_waveforms.mjs',root)),...args],
      {cwd:fileURLToPath(root),env:{...process.env,SVS_SOURCE:'missing-original-input'},timeout:10000}),error=>{
      assert.match(error.stderr,/Select one original sample context rate/);
      assert.doesNotMatch(error.stderr,/ENOENT|Chromium/);
      return true;
    });
});
