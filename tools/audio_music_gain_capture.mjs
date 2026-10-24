import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';
import {updateFixtureSections} from './fixture_sections.mjs';
import {captureGenerator,verifyGenerator} from './source_provenance.mjs';

export async function publishAudioMusicGain(root,source,{playwrightModule,chrome}={}) {
  const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
  const input=join(source,'public/js/audio.js'),destination=join(root,'data/fixtures.json');
  const sourceBytes=await readFile(input),provenance=await readFile(join(root,'data/provenance.json'));
  const expected=JSON.parse(provenance).inputs['public/js/audio.js'];
  const normalized=sourceBytes.toString('utf8').replace(/\r\n?/g,'\n');
  if(![sourceBytes,normalized,normalized.replace(/\n/g,'\r\n')].some(bytes=>digest(bytes)===expected))
    throw new Error('Procedural gain source differs from published provenance; run the complete source importer first');
  const previous=await readFile(destination),fixtures=JSON.parse(previous);
  const producer=await captureGenerator(root);
  const runtime=await import(pathToFileURL(playwrightModule||join(source,'tools/pw.mjs')).href);
  const chromium=runtime.chromium||await runtime.chromiumOrNull();
  if(!chromium)throw new Error('Original procedural gain capture requires development Playwright');
  const executablePath=chrome||(typeof runtime.chromePath==='function'?runtime.chromePath():runtime.chromePath);
  const browser=await chromium.launch({headless:true,...(executablePath?{executablePath}:{})});
  try {fixtures.audioMusicGain=await captureAudioMusicGain(await browser.newPage(),source);}
  finally {await browser.close();}
  // Do not overwrite another publisher's work or silently attach probes to new source.
  for(const [path,bytes]of [[input,sourceBytes],[destination,previous],[join(root,'data/provenance.json'),provenance]])
    if(digest(await readFile(path))!==digest(bytes))throw new Error('Source publication changed during gain capture: '+path);
  await verifyGenerator(root,producer);
  if(fixtures.fixtureFormat==='source-sections-v1')await updateFixtureSections(destination,{audioMusicGain:fixtures.audioMusicGain},{expectedRegistry:previous,projectRoot:root,producer});
  else await writeFixtureJson(destination,fixtures);
  console.log('AUDIO_MUSIC_GAIN_PUBLISHED '+JSON.stringify({source:expected,cases:fixtures.audioMusicGain.length,
    probes:fixtures.audioMusicGain.reduce((count,fixture)=>count+fixture.probes.length,0)}));
}

export async function captureAudioMusicGain(page,source) {
  const script=(await readFile(join(source,'public/js/audio.js'),'utf8')).replace(/\r\n?/g,'\n');
  return page.evaluate(async script=>{
    const cases=[];
    const quantum=128;
    const programs=[
      [[0,'start','menu'],[100,'volume',.8],[200,'volume',0],[300,'volume',.3],[400,'stop'],[663,'expire']],
      [[0,'start','menu'],[100,'start','menu'],[200,'start','battle'],[300,'volume',.7],[400,'stop'],[463,'expire'],[663,'expire']],
      [[0,'start','battle'],[100,'stop'],[150,'start','menu'],[363,'expire'],[700,'volume',0],[800,'stop'],[1063,'expire']],
      [[0,'start','menu'],[800,'stop'],[1063,'expire']],
      [[0,'start','menu'],[100,'volume',.8],[600,'volume',.2],[700,'volume',.9],[850,'stop'],[1113,'expire']],
      [[0,'start','menu'],[100,'volume',.8],[100,'volume',.25],[101,'volume',0],[102,'volume',1],[700,'stop'],[963,'expire']],
      [[0,'enabled',false],[0,'start','menu'],[100,'enabled',true],[700,'volume',0],[800,'stop'],[1063,'expire']],
      [[0,'volume',0],[0,'start','battle'],[650,'volume',1],[750,'volume',0],[800,'stop'],[1063,'expire']],
      [[0,'start','menu'],[562.5,'volume',.6],[750,'stop'],[1013,'expire']],
      [[0,'start','menu'],[562.5,'stop'],[825.5,'expire']],
      [[0,'start','menu'],[100,'volume',.8],[563,'start','battle'],[600,'stop'],[826,'expire'],[863,'expire']],
      [[0,'start','menu'],[700,'volume',1],[1500,'stop'],[1763,'expire']],
      [[0,'start','battle'],[700,'volume',.05],[1500,'volume',0],[2100,'stop'],[2363,'expire']]
    ];
    for(const rate of [32000,44100,48000,96000])for(const program of programs){
      const scheduled=program.map(([block,...action])=>[Math.round(block*rate/48000),...action]);
      const length=(scheduled.at(-1)[0]+Math.ceil(150*rate/48000))*quantum;
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
      const actions=scheduled.map(([block,op,value])=>({time:block*quantum/rate,op,...(value===undefined?{}:{value})}));
      function apply(action){
        if(action.op==='start'){
          const previous=audio._proc;audio._procStart(action.value);
          if(previous!==audio._proc){
            outlets.at(-1).initial=audio._proc.out.gain.value;
            const constant=context.createConstantSource();constant.offset.value=1;constant.connect(audio._proc.out);constant.start();
          }
        }else if(action.op==='volume')audio.setBgm(action.value);
        else if(action.op==='enabled')audio.setBgmOn(action.value);
        else if(action.op==='stop')audio._procStop();
        else if(action.op==='expire')for(const timer of timers)if(!timer.done&&timer.due<=context.currentTime+1e-8){timer.done=true;timer.callback();}
        automation.push({...action,time:context.currentTime,index:Math.round(context.currentTime*rate),active:audio._proc?.mood??null});
      }
      const groups=[];
      for(const action of actions){
        if(groups.at(-1)?.[0].time===action.time)groups.at(-1).push(action);
        else groups.push([action]);
      }
      for(const action of groups[0])apply(action);
      const suspensions=groups.slice(1).map(group=>context.suspend(group[0].time));
      const rendering=context.startRendering();
      for(let index=1;index<groups.length;index++){
        await suspensions[index-1];for(const action of groups[index])apply(action);await context.resume();
      }
      const rendered=await rendering,values=rendered.getChannelData(0),indices=new Set([0,1,length-1]);
      for(const action of automation)for(const offset of [-1,0,1,127,128,480,2400]){
        const index=Math.round(action.time*rate)+offset;
        if(index>=0&&index<length)indices.add(index);
      }
      // Dense boundaries catch one-sample ordering and endpoint discontinuities.
      const boundaries=[...automation.map(action=>action.index),...outlets.flatMap(outlet=>outlet.events.flatMap(event=>{
        if(event.operation==='exponentialRampToValueAtTime')return [Math.round(event.values[1]*rate)];
        if(event.operation==='setTargetAtTime')return [Math.round((event.values[1]+10*event.values[2])*rate)];
        return [];
      }))];
      for(const boundary of boundaries)for(let offset=-128;offset<=128;offset++){
        const index=boundary+offset;if(index>=0&&index<length)indices.add(index);
      }
      for(let index=0;index<length;index+=4096)indices.add(index);
      cases.push({sampleRate:rate,actions:automation,outlets,probes:[...indices].sort((a,b)=>a-b).map(index=>({index,value:values[index]}))});
    }
    return cases;
  },script);
}
