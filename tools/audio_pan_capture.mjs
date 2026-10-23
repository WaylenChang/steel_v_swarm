import {readFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function captureAudioPan(page,source) {
  const script=(await readFile(join(source,'public/js/audio.js'),'utf8')).replace(/\r\n?/g,'\n');
  return page.evaluate(async script=>{
    const GameAudio=new Function(script.replace(/^import .*$/gm,'').replace(/^export /gm,'')+'\nreturn GameAudio;')();
    const cases=[];
    for(const pan of [-1,-.75,-.25,0,.25,.75,1])for(const input of [[1],[1,0],[0,1]]) {
      const context=new OfflineAudioContext(2,128,48000);
      const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:context,_sfx:context.destination});
      const buffer=context.createBuffer(input.length,128,48000);
      input.forEach((gain,channel)=>{buffer.getChannelData(channel)[16]=gain;});
      const player=context.createBufferSource();player.buffer=buffer;player.connect(audio._bus(pan));player.start();
      const rendered=await context.startRendering();
      cases.push({pan,input,left:rendered.getChannelData(0)[16],right:rendered.getChannelData(1)[16]});
    }
    return cases;
  },script);
}
