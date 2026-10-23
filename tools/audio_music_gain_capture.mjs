import {readFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function captureAudioMusicGain(page,source) {
  const script=(await readFile(join(source,'public/js/audio.js'),'utf8')).replace(/\r\n?/g,'\n');
  return page.evaluate(async script=>{
    const cases=[];
    const rate=48000,quantum=128;
    const programs=[
      [[0,'start','menu'],[100,'volume',.8],[200,'volume',0],[300,'volume',.3],[400,'stop'],[663,'expire']],
      [[0,'start','menu'],[100,'start','menu'],[200,'start','battle'],[300,'volume',.7],[400,'stop'],[463,'expire'],[663,'expire']],
      [[0,'start','battle'],[100,'stop'],[150,'start','menu'],[363,'expire'],[700,'volume',0],[800,'stop'],[1063,'expire']]
    ];
    for(const program of programs){
      const length=(program.at(-1)[0]+150)*quantum;
      const context=new OfflineAudioContext(1,length,rate);
      const master=context.createGain();master.connect(context.destination);
      const timers=[],automation=[],outlets=[];
      const GameAudio=new Function('setInterval','clearInterval','setTimeout','window','localStorage','lowPower',script.replace(/^import .*$/gm,'').replace(/^export /gm,'')+'\nreturn GameAudio;')(
        ()=>0,()=>{},(callback,delay)=>{timers.push({callback,due:context.currentTime+delay/1000});return timers.length;},
        {addEventListener(){},removeEventListener(){}},{getItem:()=>null,setItem(){}},()=>false);
      const originalGain=context.createGain.bind(context);
      context.createGain=()=>{
        const node=originalGain(),record={id:outlets.length,created:context.currentTime,events:[]};
        outlets.push(record);
        for(const operation of ['exponentialRampToValueAtTime','setTargetAtTime','cancelScheduledValues']){
          const original=node.gain[operation].bind(node.gain);
          node.gain[operation]=(...values)=>{record.events.push({at:context.currentTime,operation,values});return original(...values);};
        }
        return node;
      };
      const audio=Object.assign(new GameAudio(),{_ctx:context,_master:master,_sfx:null,_save(){}});
      const actions=program.map(([block,op,value])=>({time:block*quantum/rate,op,...(value===undefined?{}:{value})}));
      function apply(action){
        if(action.op==='start'){
          const previous=audio._proc;audio._procStart(action.value);
          if(previous!==audio._proc){
            outlets.at(-1).initial=audio._proc.out.gain.value;
            const constant=context.createConstantSource();constant.offset.value=1;constant.connect(audio._proc.out);constant.start();
          }
        }else if(action.op==='volume')audio.setBgm(action.value);
        else if(action.op==='stop')audio._procStop();
        else if(action.op==='expire')for(const timer of timers)if(!timer.done&&timer.due<=context.currentTime+1e-8){timer.done=true;timer.callback();}
        automation.push({...action,time:context.currentTime,active:audio._proc?.mood??null});
      }
      apply(actions[0]);
      const suspensions=actions.slice(1).map(action=>context.suspend(action.time));
      const rendering=context.startRendering();
      for(let index=1;index<actions.length;index++){
        await suspensions[index-1];apply(actions[index]);await context.resume();
      }
      const rendered=await rendering,values=rendered.getChannelData(0),indices=new Set([0,1,length-1]);
      for(const action of automation)for(const offset of [-1,0,1,127,128,480,2400]){
        const index=Math.round(action.time*rate)+offset;
        if(index>=0&&index<length)indices.add(index);
      }
      cases.push({sampleRate:rate,actions:automation,outlets,probes:[...indices].sort((a,b)=>a-b).map(index=>({index,value:values[index]}))});
    }
    return cases;
  },script);
}
