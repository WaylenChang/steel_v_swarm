import {readFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function captureAudioAmbience(page,source) {
  const script=(await readFile(join(source,'public/js/audio.js'),'utf8')).replace(/\r\n?/g,'\n');
  return page.evaluate(async script=>{
    class Media {play(){return Promise.resolve();}}
    const {GameAudio,definitions}=new Function('Audio',script.replace(/^import .*$/gm,'').replace(/^export /gm,'')+
      '\nreturn {GameAudio,definitions:[AMB_BASE,...AMBIENCE]};')(Media);
    const cases=[];
    for(const definition of definitions){
      const rate=48000,length=60000;
      const context=new OfflineAudioContext(1,length,rate);
      let now=0;
      const wrapper={get currentTime(){return now;},createGain:()=>context.createGain(),
        createMediaElementSource(){const source=context.createConstantSource();source.offset.value=1;source.start();return source;}};
      const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:wrapper,_sfx:context.destination,_dead:false,lowPower:false,_amb:{}});
      const events=[{time:0,low:false,volume:definition.vol},{time:.125,low:false,volume:0},
        {time:.275,low:false,volume:definition.vol*.3},{time:.45,low:true,volume:definition.vol},
        {time:.65,low:false,volume:definition.vol},{time:.9,low:false,volume:0}];
      for(const event of events){now=event.time;audio.lowPower=event.low;audio._ambRide(definition,event.volume);}
      const rendered=await context.startRendering(),values=rendered.getChannelData(0);
      const indices=new Set([0,1,128,480,2400,4800,length-1]);
      for(const event of events)for(const offset of [-1,0,1,127,128,480,2400]){
        const index=Math.round(event.time*rate)+offset;
        if(index>=0&&index<length)indices.add(index);
      }
      cases.push({id:definition.id,sampleRate:rate,events,probes:[...indices].sort((a,b)=>a-b).map(index=>({index,value:values[index]}))});
    }
    return cases;
  },script);
}
