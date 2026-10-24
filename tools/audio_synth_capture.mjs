// Runs only in the offline source importer, inside its reference browser.
export async function captureSynthStems(api,probes,noise,sampleRate,moveGraphs,captureFilters) {
  const result=[];
  const encode=values=>{
    const bytes=new Uint8Array(values.length*4),view=new DataView(bytes.buffer),chunks=[];
    values.forEach((value,index)=>view.setFloat32(index*4,value,true));
    for(let index=0;index<bytes.length;index+=8192)chunks.push(String.fromCharCode(...bytes.subarray(index,index+8192)));
    return btoa(chunks.join(''));
  };
  for(const id of new Set(probes.map(probe=>probe.id))){
    const references=probes.filter(probe=>probe.id===id),base=references.find(probe=>probe.gain===1);
    if(!base)throw new Error('Missing unity graph for original synthesis: '+id);
    // Zero is symbolic here: some original manual ramps reject zero at playback.
    // Record calls without rendering so source Math.max floors can be identified.
    const symbolic=[];
    const parameter=()=>({events:[],setValueAtTime(...values){this.events.push({operation:'setValueAtTime',values});},
      exponentialRampToValueAtTime(...values){this.events.push({operation:'exponentialRampToValueAtTime',values});},
      linearRampToValueAtTime(...values){this.events.push({operation:'linearRampToValueAtTime',values});}});
    const clock={currentTime:0};
    for(const kind of ['createGain','createOscillator','createBiquadFilter','createBufferSource'])clock[kind]=()=>{
      const node={kind,connect(){},disconnect(){},start(){},stop(){}};
      for(const key of ['gain','frequency','detune','Q','playbackRate'])node[key]=parameter();
      symbolic.push(node);return node;
    };
    const symbolicAudio=Object.assign(Object.create(api.GameAudio.prototype),{_ctx:clock,_noise:noise,_sfx:clock.createGain(),
      _bus:()=>clock.createGain(),_count(){}});
    symbolicAudio._synth(id,0,0);
    if(symbolic.length!==base.graph.nodes.length)throw new Error('Gain-dependent synthesis topology: '+id);
    const dynamic=[];
    for(const node of base.graph.nodes){
      if(symbolic[node.id].kind!==node.kind)throw new Error('Unstable synthesis node order: '+id);
      if(node.kind!=='createGain')continue;
      let depends=false;
      const envelope=node.parameters.gain.events.map((event,index)=>{
        if(!['setValueAtTime','exponentialRampToValueAtTime','linearRampToValueAtTime'].includes(event.operation))throw new Error('Unsupported original SFX envelope event');
        const zero=symbolic[node.id].gain.events[index];
        if(!zero||zero.operation!==event.operation||zero.values[1]!==event.values[1])throw new Error('Gain-dependent envelope timing: '+id);
        const value=event.values[0],floor=zero.values[0];
        if(Math.abs(value-floor)<1e-12)return {operation:event.operation,time:event.values[1],constant:value};
        depends=true;
        const high=references.find(reference=>reference.gain>1),highValue=high.graph.nodes[node.id].parameters.gain.events[index].values[0];
        const scale=(highValue-value)/(high.gain-1);
        for(const reference of references){
          const actual=reference.graph.nodes[node.id].parameters.gain.events[index];
          if(actual.operation!==event.operation||actual.values[1]!==event.values[1]||Math.abs(actual.values[0]-Math.max(floor,reference.gain*scale))>1e-8)throw new Error('Unsupported nonlinear source SFX gain expression: '+id);
        }
        return {operation:event.operation,time:event.values[1],scale,floor};
      });
      if(depends)dynamic.push({node:node.id,envelope});
    }
    if(!dynamic.length)throw new Error('Missing original SFX envelope: '+id);
    const frames=Math.max(...references.map(reference=>reference.frames));
    const context=new OfflineAudioContext(dynamic.length,sampleRate*2,sampleRate);
    const merger=context.createChannelMerger(dynamic.length);merger.connect(context.destination);
    const dynamicIds=new Set(dynamic.map(stem=>stem.node));
    const nodes=base.graph.nodes.map(record=>{
      const node=context[record.kind]();
      if(record.type!==undefined)node.type=record.type;
      if(record.loop!==undefined)node.loop=record.loop;
      if(record.buffer)node.buffer=noise;
      for(const [key,parameter]of Object.entries(record.parameters)){
        node[key].value=dynamicIds.has(record.id)&&key==='gain'?1:parameter.initial;
        if(dynamicIds.has(record.id)&&key==='gain')continue;
        for(const event of parameter.events)node[key][event.operation](...event.values);
      }
      return node;
    });
    for(const connection of base.graph.connections){
      if(dynamicIds.has(connection.from)||connection.to==='output')continue;
      const destination=typeof connection.to==='object'?nodes[connection.to.node][connection.to.parameter]:nodes[connection.to];
      nodes[connection.from].connect(destination,...connection.indices);
    }
    dynamic.forEach((stem,index)=>nodes[stem.node].connect(merger,0,index));
    for(const record of base.graph.nodes){
      for(const values of record.starts)nodes[record.id].start(...values);
      for(const values of record.stops)nodes[record.id].stop(...values);
    }
    const rendered=await context.startRendering();
    const stems=dynamic.map((stem,index)=>{
      let current=stem.node,route=null;
      const effects=[],visited=new Set();
      while(!route){
        if(visited.has(current))throw new Error('Cyclic original SFX output graph: '+id);
        visited.add(current);
        const edges=base.graph.connections.filter(edge=>edge.from===current);
        if(edges.length!==1)throw new Error('Unsupported branched original SFX output: '+id);
        const edge=edges[0];
        if(edge.to==='output'){route=edge.indices[1]===0?'panned':'centered';break;}
        if(typeof edge.to!=='number')throw new Error('Unsupported SFX parameter output');
        const next=base.graph.nodes[edge.to];
        if(next.kind==='createBiquadFilter')effects.push(next);
        else if(next.kind!=='createGain'||next.parameters.gain.initial!==1||next.parameters.gain.events.length)throw new Error('Unsupported source SFX post-envelope node');
        current=edge.to;
      }
      return {...stem,route,effects,values:encode(rendered.getChannelData(index).subarray(0,frames))};
    });
    result.push({id,sampleRate,frames,reservationSeconds:base.reservationSeconds,maximumGain:Math.max(...references.map(reference=>reference.gain)),stems});
  }
  const filterNodes=[...result.flatMap(sound=>sound.stems.flatMap(stem=>stem.effects)),
    ...Object.values(moveGraphs).flatMap(graph=>graph.nodes.filter(node=>node.kind==='createBiquadFilter'))];
  return {sounds:result,filters:await captureFilters(filterNodes)};
}

export async function captureFilterImpulses(filterNodes) {
  const filters=[],seen=new Set();
  for(const effect of filterNodes){
    const key=JSON.stringify({type:effect.type,parameters:effect.parameters});
    if(seen.has(key))continue;
    seen.add(key);
    const responses={};
    for(const rate of [44100,48000,96000]){
      const context=new OfflineAudioContext(1,1024,rate),filter=context.createBiquadFilter();
      filter.type=effect.type;
      for(const [name,parameter]of Object.entries(effect.parameters)){
        filter[name].value=parameter.initial;
        for(const event of parameter.events)filter[name][event.operation](...event.values);
      }
      const buffer=context.createBuffer(1,1024,rate);buffer.getChannelData(0)[128]=1;
      const input=context.createBufferSource();input.buffer=buffer;input.connect(filter);filter.connect(context.destination);input.start();
      const rendered=await context.startRendering();
      responses[rate]=Array.from(rendered.getChannelData(0).subarray(128,640));
    }
    filters.push({effect,responses});
  }
  return filters;
}
