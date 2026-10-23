import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function roomMemberReferences(source,d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const text=(await readFile(join(source,'server/rooms.js'),'utf8')).replace(/\r\n?/g,'\n');
  const Hub=new Function('CHARACTERS','SIDES','BOT_DIFF','setTimeout','return class {\n'+
    ['attach','_sideCount','leaveRoom'].map(name=>grabMethod(text,name)).join('\n')+'\n};')(d.CHARACTERS,d.SIDES,d.BOT_DIFF,()=>{});
  const steel=d.charsOf('STEEL').find(id=>d.CHARACTERS[id].side==='STEEL');
  const swarm=d.charsOf('SWARM').find(id=>d.CHARACTERS[id].side==='SWARM');
  const merc=d.charsOf('STEEL').find(id=>d.CHARACTERS[id].side==='MERC');
  const launch=grabMethod(text,'startBattle');
  const slices=launch.indexOf('const snaps = {};');
  const slicesEnd=launch.indexOf('if (room.battle.over)',slices);
  if(slices<0||slicesEnd<0)throw new Error('Missing original recipient vision publication');
  const publish=new Function('room',launch.slice(slices,slicesEnd));
  const create=(capacity,superMode,definitions,bots=[])=>{
    const hub=new Hub(),connections=new Map(),errors=[];
    const room={pin:'1234',phase:'room',hostId:42,config:{teamSize:capacity,botDiff:d.DEFAULT_BOT_DIFF},battleConfig:{super:superMode},battle:null,
      clients:new Map(definitions.map(([player,side,mode,ch],index)=>[player,{side:side||null,mode,ch:ch||null,token:'test-'+index,connected:true,ready:false,loaded:false,send:()=>{}}])),
      bots:new Map(bots.map((side,index)=>['b'+(index+1),{side,name:d.BOT_NAMES[index]}]))};
    Object.assign(hub,{rooms:new Map([[room.pin,room]]),_nextClientId:1000,dropMs:1,log:()=>{},broadcast:()=>{},osmPayload:()=>null,stopBattle:()=>{},maybeLaunch:()=>{}});
    for(let index=0;index<definitions.length;index++) {
      const connection=hub.attach(message=>{if(message.t==='error')errors.push(message.msg);});
      connections.set(connection.id,connection);connection.recv({t:'reattach',token:'test-'+index});
    }
    return {hub,room,connections,errors};
  };
  const scenarios=[
    {name:'side-character-ready',capacity:2,superMode:false,definitions:[[42,'STEEL','player',steel],[43,'SWARM','player',swarm]],bots:['SWARM'],operations:[
      ['loaded',1000],['ready',1000,true],['character',1000,merc],['side',1000,'SWARM'],['removeBot',1000,-1],
      ['side',1000,'SWARM'],['character',1000,merc],['ready',1000,true],['side',1000,'SWARM'],
      ['character',1000,steel],['character',1000,'missing-character'],['character',1000,merc],['ready',1000,true],
      ['character',1000,''],['side',1000,''],['character',1000,merc],['ready',1000,true],['side',1000,'invalid'],
      ['side',1000,'STEEL'],['character',1000,steel],['phase','loading'],['character',1000,merc],
      ['phase','game'],['character',1000,merc]]},
    {name:'spectator-exclusion',capacity:2,superMode:false,definitions:[[42,'','spectator',''],[43,'STEEL','player',steel]],bots:[],operations:[
      ['side',1000,'STEEL'],['character',1000,merc],['ready',1000,true],['loaded',1000]]},
    {name:'live-side-metadata',capacity:2,superMode:false,definitions:[[42,'STEEL','player',steel],[43,'SWARM','player',swarm],[44,'','spectator','']],bots:[],operations:[
      ...['loading','game','over'].flatMap(phase=>[['phase',phase],['ready',1000,true],['side',1000,'SWARM'],
        ['character',1000,merc],['side',1000,'SWARM'],['side',1000,''],['side',1002,'STEEL'],
        ['side',1000,'invalid'],['side',1000,'SUPER'],['side',1000,'STEEL']])]},
    {name:'live-super-side-policy',capacity:2,superMode:true,definitions:[[42,'SUPER','player',steel],[43,'','player','']],bots:[],operations:[
      ['phase','game'],['side',1001,'SUPER'],['side',1000,'STEEL'],['side',1001,'SUPER'],
      ['side',1000,'SUPER'],['side',1001,''],['side',1000,'SUPER']]},
    {name:'super-seat-and-pool',capacity:5,superMode:true,definitions:[[42,'SUPER','player',steel],[43,'','player','']],bots:[],operations:[
      ['side',1001,'SUPER'],['side',1000,'STEEL'],['side',1001,'SUPER'],['character',1001,swarm],
      ['character',1001,steel],['character',1001,merc]]},
    {name:'host-difficulty-transfer',capacity:1,superMode:false,definitions:[[42,'STEEL','player',steel],[43,'SWARM','player',swarm]],bots:[],operations:[
      ...['room','loading','game','over'].flatMap(phase=>[['phase',phase],['difficulty',1001,'high'],['difficulty',1000,'high'],['difficulty',1000,'invalid'],['difficulty',1000,'novice']]),
      ['leave',1000],['difficulty',1000,'high'],['difficulty',1001,'high']]},
  ];
  const main=(await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n');
  const leaveSeat=/slotX\('([^']+)', \(\) => app\.net\?\.send\(\{ t: 'pickSide', side: null \}\)\)/.exec(main);
  if(!leaveSeat)throw new Error('Missing original leave-seat control');
  const programs=[],ui={room_leave_seat:leaveSeat[1]};
  for(const scenario of scenarios) {
    const {room,connections,errors}=create(scenario.capacity,scenario.superMode,scenario.definitions,scenario.bots);
    const snapshot=()=>{
      const vision={};
      publish({battle:{snapshotFor:side=>side||''},clients:new Map([...room.clients].map(([id,member])=>[id,{side:member.side,send:slice=>{vision[id]=slice;}}]))});
      return {host:room.hostId,phase:room.phase,difficulty:room.config.botDiff,vision,
        members:[...room.clients].map(([player,member])=>({player,side:member.side||'',mode:member.mode,character:member.ch||'',ready:member.ready,loaded:member.loaded}))};
    };
    const initial=snapshot(),frames=[];
    for(const operation of scenario.operations) {
      errors.length=0;
      const [kind,transport,value]=operation;
      if(kind==='phase')room.phase=transport;
      else if(kind==='side')connections.get(transport).recv({t:'pickSide',side:value||null});
      else if(kind==='character')connections.get(transport).recv({t:'pickChar',ch:value||null});
      else if(kind==='ready')connections.get(transport).recv({t:'setReady',ready:value});
      else if(kind==='loaded')connections.get(transport).recv({t:'loaded'});
      else if(kind==='difficulty')connections.get(transport).recv({t:'setRoomConfig',botDiff:value});
      else if(kind==='leave')connections.get(transport).recv({t:'leaveRoom'});
      else if(kind==='removeBot')connections.get(transport).recv({t:'removeBot',id:'b'+(-value)});
      if(kind==='character'&&errors.length)ui.room_character_invalid=errors[0];
      if(kind==='side'&&scenario.name==='spectator-exclusion'&&errors.length)ui.room_spectator_side=errors[0];
      frames.push({operation,errors:errors.slice(),...snapshot()});
    }
    programs.push({...scenario,initial,frames});
  }
  for(const side of ['STEEL','SWARM',d.SUPER_SIDE])for(let capacity=d.TEAM.MIN;capacity<=d.TEAM.MAX;capacity++) {
    if(side===d.SUPER_SIDE&&capacity!==1)continue;
    const definitions=[[42,'','player',''],...Array.from({length:capacity},(_,index)=>[43+index,side,'player',''])];
    const {connections,errors}=create(capacity,side===d.SUPER_SIDE,definitions);
    connections.get(1000).recv({t:'pickSide',side});
    if(errors.length!==1)throw new Error('Missing original full-side rejection');
    ui['room_side_full_'+side+'_'+capacity]=errors[0];
  }
  if(!ui.room_character_invalid||!ui.room_spectator_side)throw new Error('Missing original player selection notices');
  return {ui,fixtures:{roomMemberPrograms:programs},inputs:['server/rooms.js','public/js/data.js','public/js/main.js']};
}
