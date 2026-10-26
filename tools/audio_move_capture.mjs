// Runs inside the offline reference browser; runtime playback uses native assets.
export async function captureMoveBank(graphs,noise,{nativeRate=false}={}) {
  const encode=values=>{
    const bytes=new Uint8Array(values.length*4),view=new DataView(bytes.buffer),chunks=[];
    values.forEach((value,index)=>view.setFloat32(index*4,value,true));
    for(let index=0;index<bytes.length;index+=8192)chunks.push(String.fromCharCode(...bytes.subarray(index,index+8192)));
    return btoa(chunks.join(''));
  };
  const oscillators=[];
  for(const [category,graph]of Object.entries(graphs))for(const node of graph.nodes){
    if(node.kind!=='createOscillator')continue;
    const frequency=node.parameters.frequency.initial;
    let frames=Math.round(48000/frequency),rate=frames*frequency,cycles=1;
    const lfo=graph.connections.some(edge=>edge.from===node.id&&graph.connections.some(next=>
      next.from===edge.to&&typeof next.to==='object'));
    if(nativeRate&&!lfo) {
      if(!Number.isSafeInteger(frequency)||!Number.isSafeInteger(noise.sampleRate))throw new Error('Unsupported exact native movement oscillator period');
      const gcd=(a,b)=>b?gcd(b,a%b):a,divisor=gcd(noise.sampleRate,frequency);
      frames=noise.sampleRate/divisor;rate=noise.sampleRate;cycles=frequency/divisor;
    }
    if(frames<2||rate<8000||rate>384000)throw new Error('Unsupported original movement oscillator representation');
    const context=new OfflineAudioContext(1,frames,rate),oscillator=context.createOscillator();
    oscillator.type=node.type;
    for(const [key,parameter]of Object.entries(node.parameters)){
      oscillator[key].value=parameter.initial;
      if(parameter.events.length)throw new Error('Unexpected initial movement oscillator automation');
    }
    oscillator.connect(context.destination);oscillator.start();
    const rendered=await context.startRendering();
    oscillators.push({category,node:node.id,type:node.type,frequency,frames,sampleRate:rendered.sampleRate,...(cycles!==1?{cycles}:{}),
      values:encode(rendered.getChannelData(0))});
  }
  return {oscillators,noise:{sampleRate:noise.sampleRate,frames:noise.length,encoding:'float32le',values:encode(noise.getChannelData(0))}};
}
