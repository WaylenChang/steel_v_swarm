import assert from 'node:assert/strict';

function decodeWords(encoded,frames) {
  assert.equal(typeof encoded,'string');
  const bytes=Buffer.from(encoded,'base64');
  assert.equal(bytes.length,frames*4,'Complete oscillator witness');
  assert.equal(bytes.toString('base64'),encoded,'Canonical oscillator witness');
  const values=new Float32Array(frames);
  for(let index=0;index<frames;index++) {
    values[index]=bytes.readFloatLE(index*4);
    assert.ok(Number.isFinite(values[index]),'Finite oscillator witness');
  }
  return values;
}

export function oscillatorWitnessErrors(witness,period,sampleRate) {
  const actual=decodeWords(witness.values,witness.frames);
  const frequency=decodeWords(witness.frequencyValues,witness.frames);
  const table=decodeWords(period.values,period.frames),cycles=period.cycles??1;
  assert.ok(Number.isSafeInteger(cycles)&&cycles>=1&&cycles<=period.frames);
  for(const value of frequency)assert.ok(value>0&&value<sampleRate/2,'Unclipped original frequency timeline');
  // Candidate phase model from Chromium 151; this does not reproduce its wave-table selection or SIMD interpolation.
  const tableSize=sampleRate<=24000?2048:(sampleRate<=88200?4096:16384);
  const rateScale=Math.fround(tableSize/sampleRate);
  const errors={controlHz:0,scalarPeriod:0,measuredControlPeriod:0,roundedIncrementPeriod:0};
  const phases=[0,0,0];
  let value=1,target=1,decay=1,cursor=0;
  for(let index=0;index<witness.frames;index++) {
    while(cursor<witness.commands.length&&Math.ceil(witness.commands[cursor].time*sampleRate)<=index) {
      const event=witness.commands[cursor++];
      target=event.target;decay=Math.exp(-1/(sampleRate*event.tau));
    }
    errors.controlHz=Math.max(errors.controlHz,Math.abs(frequency[index]-period.frequency*value));
    for(const [model,key]of ['scalarPeriod','measuredControlPeriod','roundedIncrementPeriod'].entries()) {
      const position=phases[model]*table.length,begin=Math.floor(position);
      const output=table[begin]+(table[(begin+1)%table.length]-table[begin])*(position-begin);
      errors[key]=Math.max(errors[key],Math.abs(output-actual[index]));
    }
    const steps=[period.frequency*value/sampleRate,frequency[index]/sampleRate,
      Math.fround(frequency[index]*rateScale)/tableSize];
    for(let model=0;model<3;model++)phases[model]=(phases[model]+steps[model]/cycles)%1;
    value=target+(value-target)*decay;
  }
  return errors;
}

export async function captureAudioMoveOscillators(page,movement,program) {
  assert.equal(movement.scope,'original-movement-shared-sfx-rate');
  assert.equal(program.scope,'original-movement-rate-waveforms');
  const sampleRate=movement.sampleRate;
  assert.ok(Number.isSafeInteger(sampleRate)&&sampleRate>=8000&&sampleRate<=384000);
  assert.equal(program.sampleRate,sampleRate);
  assert.equal(program.frames,sampleRate);
  assert.equal(program.source.audioSha256,movement.source.audioSha256);
  const inputs=movement.oscillators.map(period=>{
    const graph=movement.graphs[period.category],node=graph.nodes.find(item=>item.id===period.node);
    assert.equal(node.kind,'createOscillator');assert.equal(node.type,period.type);
    assert.equal(node.parameters.frequency.initial,period.frequency);
    assert.ok(period.frequency>0&&period.frequency<sampleRate/2);
    decodeWords(period.values,period.frames);
    const fixture=program.waveforms.find(item=>item.category===period.category);
    assert.ok(fixture,'Original oscillator command program');
    const commands=fixture.commands.filter(command=>command.key==='rate'&&
      command.binding.node===period.node&&command.binding.parameter==='frequency');
    let previous=-1;
    for(const command of commands) {
      assert.equal(command.base,period.frequency);
      assert.equal(command.parameterTarget,command.base*command.target);
      assert.ok(Number.isFinite(command.parameterTarget)&&command.parameterTarget>0&&command.parameterTarget<sampleRate/2);
      assert.ok(Number.isFinite(command.time)&&command.time>=0&&command.time>previous&&command.time<1);
      assert.ok(Number.isFinite(command.tau)&&command.tau>0);previous=command.time;
    }
    assert.equal(commands.length,graph.rate.some(binding=>binding.parameter.node===period.node&&
      binding.parameter.parameter==='frequency')?3:0,'Complete original oscillator automation');
    return {category:period.category,node:period.node,type:period.type,frequency:period.frequency,commands};
  });
  const witnesses=await page.evaluate(async({inputs,sampleRate})=>{
    const encode=values=>{
      const bytes=new Uint8Array(values.length*4),view=new DataView(bytes.buffer),parts=[];
      values.forEach((value,index)=>view.setFloat32(index*4,value,true));
      for(let offset=0;offset<bytes.length;offset+=8192)parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
      return btoa(parts.join(''));
    };
    const output=[];
    for(const input of inputs) {
      const context=new OfflineAudioContext(2,sampleRate,sampleRate),oscillator=context.createOscillator();
      const constant=context.createConstantSource(),parameter=context.createGain(),merger=context.createChannelMerger(2);
      oscillator.type=input.type;oscillator.frequency.value=input.frequency;
      constant.offset.value=1;parameter.gain.value=input.frequency;
      for(const command of input.commands)for(const target of [oscillator.frequency,parameter.gain])
        target.setTargetAtTime(command.parameterTarget,command.time,command.tau);
      // Observe the same AudioParam timeline in a separate channel of this render quantum.
      oscillator.connect(merger,0,0);constant.connect(parameter);parameter.connect(merger,0,1);
      merger.connect(context.destination);oscillator.start();constant.start();
      const buffer=await context.startRendering();
      output.push({...input,frames:sampleRate,values:encode(buffer.getChannelData(0)),
        frequencyValues:encode(buffer.getChannelData(1))});
    }
    return output;
  },{inputs,sampleRate});
  assert.equal(witnesses.length,inputs.length);
  return witnesses.map((witness,index)=>{
    const {frames,values,frequencyValues,...identity}=witness;
    assert.deepEqual(identity,inputs[index],'Complete ordered original oscillator witnesses');
    assert.equal(frames,sampleRate);
    return {...witness,modelErrors:oscillatorWitnessErrors(witness,movement.oscillators[index],sampleRate)};
  });
}
