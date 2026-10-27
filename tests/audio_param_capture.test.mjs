import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {captureAudioParamPrograms,movementParameterPrograms} from '../tools/audio_param_capture.mjs';
import {decodeSourceNumericPart} from '../tools/source_numeric_transfer.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const original=await readFile(join(source,'public/js/audio.js'),'utf8');
const program=JSON.parse(await readFile(join(root,'data/audio_move_rate_waveforms/48000.json'),'utf8'));

test('parameter programs preserve source multiplication targets and complementary dry expressions',()=>{
  const programs=movementParameterPrograms(program,original);
  assert.equal(programs.length,16);
  const keys=new Set(programs.flatMap(item=>item.origins.map(origin=>origin.key)));
  for(const key of ['gain','pan','wet','dry','rate:8:frequency'])assert.ok(keys.has(key));
  const rate=programs.find(item=>item.origins.some(origin=>origin.key==='rate:8:frequency'));
  assert.equal(rate.commands[1].target,2.6*1.8);
  assert.throws(()=>movementParameterPrograms(program,original.replace('1 - w, t, 0.14','w, t, 0.14')));
});

test('parameter browser transport retains every command double with the shared numeric codec',async()=>{
  let calls=0;
  const programs=[{name:'fractional',initial:1,frames:128,commands:[{target:.6,time:.5/48000,tau:.001}]}];
  const page={async evaluate(_callback,args){calls++;
    const encoded=args.programs[0].commandValues,decoded=decodeSourceNumericPart(encoded);
    assert.equal(decoded.bytes.readDoubleLE(8),.5/48000);
    return args.programs.map(item=>({...item,values:Buffer.alloc(item.frames*4).toString('base64')}));
  }};
  const result=await captureAudioParamPrograms(page,48000,programs);
  assert.equal(calls,1);assert.equal(result[0].commands[0].time,.5/48000);
});

test('invalid parameters reject before browser execution and corrupt browser output rejects',async()=>{
  const valid={name:'valid',initial:1,frames:128,commands:[{target:0,time:0,tau:.14}]};
  for(const change of [p=>p.initial=NaN,p=>p.frames=127,p=>p.commands[0].target=Infinity,
    p=>p.commands[0].time=-1,p=>p.commands[0].tau=-1]) {
    const invalid=structuredClone(valid);change(invalid);
    await assert.rejects(captureAudioParamPrograms({async evaluate(){assert.fail('Invalid program entered browser');}},48000,[invalid]));
  }
  for(const change of [items=>[],items=>{items[0].values='';return items;},
    items=>{items[0].initial++;return items;}]) {
    const page={async evaluate(_callback,args){return change(args.programs.map(item=>({...item,values:Buffer.alloc(item.frames*4).toString('base64')})));}};
    await assert.rejects(captureAudioParamPrograms(page,48000,[valid]));
  }
});

test('archived parameter words and finite outputs cover every original program and numerical boundary',async()=>{
  const data=JSON.parse(await readFile(join(root,'data/audio_move_oscillators/48000.json'),'utf8'));
  assert.equal(data.parameterProbes.length,21);
  const originals=movementParameterPrograms(program,original);
  for(const [index,probe]of data.parameterProbes.entries()) {
    if(index<originals.length) {
      const {values,commandValues,...identity}=probe;
      assert.deepEqual(identity,originals[index]);
    }
    const {bytes,rows,width}=decodeSourceNumericPart(probe.commandValues);
    assert.equal(rows,probe.commands.length);assert.equal(width,3);
    for(let index=0;index<rows;index++)for(const [column,key]of ['target','time','tau'].entries())
      assert.equal(bytes.readDoubleLE((index*3+column)*8),probe.commands[index][key]);
    const values=Buffer.from(probe.values,'base64');assert.equal(values.length,probe.frames*4);
    for(let offset=0;offset<values.length;offset+=4)assert.ok(Number.isFinite(values.readFloatLE(offset)));
  }
});
