import assert from 'node:assert/strict';
import {encodeSourceNumericPart} from './source_numeric_transfer.mjs';

export function movementParameterPrograms(program,original) {
  assert.equal(program.scope,'original-movement-rate-waveforms');
  const unique=new Map();
  for(const fixture of program.waveforms) {
    const parameters=new Map();
    for(const command of fixture.commands) {
      const key=command.key==='rate'?'rate:'+command.binding.node+':'+command.binding.parameter:command.key;
      if(!parameters.has(key))parameters.set(key,[]);
      parameters.get(key).push({target:command.key==='rate'?command.parameterTarget:command.target,
        time:command.time,tau:command.tau});
    }
    if(parameters.has('wet')) {
      assert.match(original,/v\.dry\.gain\.setTargetAtTime\(1 - w, t, 0\.14\)/,'Original complementary dry target expression');
      assert.match(original,/v\.wet\.gain\.setTargetAtTime\(w, t, 0\.14\)/,'Original wet target expression');
      parameters.set('dry',parameters.get('wet').map(command=>({...command,target:1-command.target})));
    }
    for(const [key,commands]of parameters) {
      const initial=key.startsWith('rate:')?fixture.commands.find(command=>command.key==='rate'&&
        key==='rate:'+command.binding.node+':'+command.binding.parameter).base:
        (key==='dry'?1-fixture.wet:fixture[key]);
      const identity=JSON.stringify({initial,commands});
      if(!unique.has(identity))unique.set(identity,{name:key+':'+unique.size,initial,frames:program.frames,commands,origins:[]});
      unique.get(identity).origins.push({category:fixture.category,wet:fixture.wet,key});
    }
  }
  return [...unique.values()];
}

export async function captureAudioParamPrograms(page,sampleRate,programs) {
  assert.ok(Number.isSafeInteger(sampleRate)&&sampleRate>=8000&&sampleRate<=384000);
  for(const program of programs) {
    assert.ok(Number.isFinite(program.initial)&&Number.isFinite(Math.fround(program.initial)));
    assert.ok(Number.isSafeInteger(program.frames)&&program.frames>0&&program.frames%128===0);
    for(const command of program.commands) {
      assert.ok(Number.isFinite(command.target)&&Number.isFinite(Math.fround(command.target)));
      assert.ok(Number.isFinite(command.time)&&command.time>=0&&command.time<program.frames/sampleRate);
      assert.ok(Number.isFinite(command.tau)&&command.tau>=0&&Number.isFinite(Math.fround(command.tau)));
    }
  }
  const inputs=programs.map(program=>({...program,commandValues:encodeSourceNumericPart(program.commands.map(command=>[command.target,command.time,command.tau]))}));
  const result=await page.evaluate(async({sampleRate,programs})=>{
    const output=[];
    for(const program of programs) {
      const context=new OfflineAudioContext(1,program.frames,sampleRate),constant=context.createConstantSource(),gain=context.createGain();
      constant.offset.value=1;gain.gain.value=program.initial;
      for(const command of program.commands)gain.gain.setTargetAtTime(command.target,command.time,command.tau);
      constant.connect(gain);gain.connect(context.destination);constant.start();
      const values=(await context.startRendering()).getChannelData(0),bytes=new Uint8Array(values.length*4),view=new DataView(bytes.buffer),parts=[];
      values.forEach((value,index)=>view.setFloat32(index*4,value,true));
      for(let offset=0;offset<bytes.length;offset+=8192)parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
      output.push({...program,values:btoa(parts.join(''))});
    }
    return output;
  },{sampleRate,programs:inputs});
  assert.equal(result.length,programs.length);
  for(const [index,program]of result.entries()) {
    const {values,...identity}=program;assert.deepEqual(identity,inputs[index]);
    const bytes=Buffer.from(values,'base64');assert.equal(bytes.length,program.frames*4);
    assert.equal(bytes.toString('base64'),values);
    for(let offset=0;offset<bytes.length;offset+=4)assert.ok(Number.isFinite(bytes.readFloatLE(offset)));
  }
  return result;
}
