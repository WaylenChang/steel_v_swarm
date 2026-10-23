import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function fatalReferences(source) {
  const {grabFn,grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const main=(await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n');
  const html=await readFile(join(source,'public/index.html'),'utf8');
  const limits=/const FATAL = (\{[^\n]+\});/.exec(main);
  const initial=/const fatal = (\{[\s\S]*?\n\});/.exec(main);
  const period=/setInterval\(fatalWatchdog, (\d+)\)/.exec(main);
  if(!limits||!initial||!period)throw new Error('Missing original fatal watchdog state/limits');
  const rules=new Function('return ('+limits[1]+');')();
  rules.POLL_MS=Number(period[1]);
  const ui={};
  for(const [id,key]of [['fatalTitle','fatal_title'],['fatalRestartBtn','fatal_restart'],['fatalCloseBtn','fatal_close']]) {
    const label=new RegExp('id="'+id+'"[^>]*>([^<]+)<').exec(html)?.[1];
    if(!label)throw new Error('Missing original fatal UI: '+id);
    ui[key]=label;
  }
  for(const [name,key]of [['地形建構失敗','fatal_world'],['戰場建立失敗','fatal_battle']]) {
    const template=new RegExp('showFatal\\(`([^`]*'+name+'[^`]*)`\\);').exec(main)?.[1];
    if(!template||!template.includes("${e.message || '未知錯誤'}"))throw new Error('Missing original fatal error template: '+name);
    ui[key]=template.replace("${e.message || '未知錯誤'}",'%s');
  }
  const fields={load_started:'loadT0',load_progress:'loadProgressAt',local_loaded:'localLoaded',last_snapshot:'lastSnap',last_frame:'lastFrame',disconnected_at:'disconnectedAt',hidden_at:'hiddenAt',shown:'shown'};
  const programs=[];
  const cases=[
    {name:'loading-strict-boundary',reason:'fatal_loading',operations:[['loading',1000],['poll',91000],['poll',91001],['poll',200000]]},
    {name:'progress-and-total-cap',reason:'fatal_loading',operations:[['loading',1000],['set',{load_progress:90000}],['poll',180000],['set',{load_progress:180000}],['poll',181000],['poll',181001]]},
    {name:'waiting-for-others',reason:'fatal_waiting',operations:[['loading',1000],['set',{local_loaded:true}],['poll',91001],['poll',181000],['poll',181001]]},
    {name:'continuous-disconnect',reason:'fatal_network',operations:[['phase','game'],['connected',false],['poll',1000],['set',{last_snapshot:40000,last_frame:40000}],['poll',31000],['poll',31001]]},
    {name:'recovery-resets-disconnect',reason:'fatal_network',operations:[['phase','game'],['set',{last_snapshot:100000,last_frame:100000}],['connected',false],['poll',1000],['connected',true],['poll',30000],['connected',false],['poll',31000],['poll',61000],['poll',61001]]},
    {name:'snapshot-stall',reason:'fatal_snapshot',operations:[['phase','game'],['set',{last_snapshot:1000,last_frame:30000}],['poll',21000],['poll',21001]]},
    {name:'frame-stall-with-packets',reason:'fatal_frame',operations:[['phase','game'],['set',{last_snapshot:30000,last_frame:1000}],['poll',21000],['poll',21001]]},
    {name:'no-battle-no-stall',reason:'',operations:[['phase','game'],['battle',false],['poll',999999],['phase','over'],['battle',true],['poll',999999],['phase','room'],['poll',999999]]},
    {name:'background-loading',reason:'fatal_loading',operations:[['loading',1000],['hidden',true,2000],['poll',500000],['hidden',false,501000],['poll',590000],['poll',590001]]},
    {name:'background-game',reason:'fatal_snapshot',operations:[['phase','game'],['set',{last_snapshot:1000,last_frame:1000}],['hidden',true,2000],['poll',999999],['hidden',false,1000000],['poll',1020000],['poll',1020001]]},
  ];
  for(const item of cases) {
    let now=1;
    const document={hidden:false},app={phaseShown:'room',net:{connected:true},battle:{}},nodes=new Map(),toasts=[];
    const $=id=>{if(!nodes.has(id))nodes.set(id,{style:{},textContent:''});return nodes.get(id);};
    const Date={now:()=>now},performance={now:()=>now};
    const fatal=new Function('Date','performance','return ('+initial[1]+');')(Date,performance);
    const functions=new Function('FATAL','fatal','app','document','Date','performance','$','netMode','toast',
      ['fatalArmed','showFatal','hideFatal','fatalWatchdog'].map(name=>grabFn(main,name)).join('\n')+
      '\nreturn {poll:fatalWatchdog,show:showFatal,hide:hideFatal};')(rules,fatal,app,document,Date,performance,$,()=> 'solo',message=>toasts.push(message));
    const visible=new Function('fatal','document','Date','performance',grabBlock(main,"document.addEventListener('visibilitychange', () =>"));
    const snapshot=()=>Object.fromEntries(Object.entries(fields).map(([native,original])=>[native,fatal[original]??0]));
    const start=snapshot(),frames=[];
    for(const operation of item.operations) {
      const [kind,value,stamp]=operation;
      if(kind==='loading') {now=value;app.phaseShown='loading';Object.assign(fatal,{loadT0:now,loadProgressAt:now,localLoaded:false,lastSnap:now,disconnectedAt:0});}
      else if(kind==='set')for(const [key,field]of Object.entries(value))fatal[fields[key]]=field;
      else if(kind==='phase')app.phaseShown=value;
      else if(kind==='connected')app.net.connected=value;
      else if(kind==='battle')app.battle=value?{}:null;
      else if(kind==='hidden') {now=stamp;document.hidden=value;visible(fatal,document,Date,performance);}
      else if(kind==='poll') {now=value;functions.poll();}
      const message=$('fatalReason').textContent;
      if(message) {
        if(!item.reason)throw new Error('Unexpected original fatal trigger: '+item.name);
        if(ui[item.reason]&&ui[item.reason]!==message)throw new Error('Inconsistent original fatal reason: '+item.reason);
        ui[item.reason]=message;
      }
      frames.push({operation,...snapshot(),hidden:document.hidden,reason:message?item.reason:''});
    }
    programs.push({...item,initial:start,frames});
  }
  for(const key of ['fatal_loading','fatal_waiting','fatal_network','fatal_snapshot','fatal_frame'])if(!ui[key])throw new Error('Missing original fatal case: '+key);
  const reveals=[];
  for(const phase of ['room','loading','game','over'])for(const force of [false,true])for(const mode of ['solo','cloud']) {
    const fatal={shown:false},app={phaseShown:phase},nodes=new Map(),toasts=[];
    const $=id=>{if(!nodes.has(id))nodes.set(id,{style:{},textContent:''});return nodes.get(id);};
    const reveal=new Function('fatal','app','$','netMode','toast',grabFn(main,'fatalArmed')+'\n'+grabFn(main,'showFatal')+'\nreturn showFatal;')(
      fatal,app,$,()=>mode,value=>toasts.push(value));
    reveal('first failure',force);reveal('second failure',force);
    reveals.push({phase,force,solo:mode==='solo',shown:fatal.shown,toasts:toasts.length,
      reason:$('fatalReason').textContent,restart:fatal.shown&&$('fatalRestartBtn').style.display!=='none'});
  }
  const restarts=[];
  for(const mode of ['solo','cloud'])for(const saved of [false,true]) {
    const calls=[],nodes=new Map(),fatal={shown:true,loadT0:100,loadProgressAt:200,localLoaded:true};
    const $=id=>{if(!nodes.has(id))nodes.set(id,{style:{},dataset:{done:true}});return nodes.get(id);};
    const app={net:{send:message=>calls.push(message.t)},battle:{dispose:()=>calls.push('disposeBattle')},dlg:{dispose:()=>calls.push('disposeDialogue')},
      terrain:{},pre:{},fieldMsg:{},story:{},super:{},quickRestart:{}};
    const execute=new Function('app','fatal','$','netMode','sessionStorage','clearOsmIn','resetOsmMisses','geoClear','connectNet','loadPrefs','quickRestartGame','show','refreshRooms','Date',
      'let _BattleClient={};\n'+['hideFatal','fatalClose','fatalRestart'].map(name=>grabFn(main,name)).join('\n')+'\nreturn fatalRestart;')(
      app,fatal,$,()=>mode,{removeItem:key=>calls.push('remove:'+key)},()=>calls.push('clearOsm'),()=>calls.push('resetOsm'),
      async()=>{calls.push('clearGeo');},()=>calls.push('connect'),()=>({lastSession:saved?{battleConfig:{}}:null}),()=>calls.push('quick'),
      screen=>calls.push('show:'+screen),()=>calls.push('refresh'),{now:()=>12345});
    await execute();
    restarts.push({solo:mode==='solo',saved,calls,cleared:['battle','dlg','terrain','pre','fieldMsg','story','super','quickRestart'].every(key=>app[key]===null),
      hidden:!fatal.shown,restarted:calls.includes('quick'),connected:calls.includes('connect')});
  }
  return {rules:{fatal:rules},ui,fixtures:{fatalPrograms:programs,fatalReveals:reveals,fatalRestarts:restarts},inputs:['public/js/main.js','public/index.html']};
}
