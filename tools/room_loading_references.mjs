import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function roomLoadingReferences(source,controls,rules) {
  const {grabMethod,grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const rooms=(await readFile(join(source,'server/rooms.js'),'utf8')).replace(/\r\n?/g,'\n');
  const main=(await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n');
  const preloadStart=main.indexOf('function renderPreloadStatus() {');
  const preloadEnd=main.indexOf('\n}',preloadStart);
  if(preloadStart<0||preloadEnd<0) throw new Error('Missing original room preload status renderer');
  const preloadRender=new Function('app','$',main.slice(preloadStart,preloadEnd+2)+'\nrenderPreloadStatus();');
  const preloadText=pre=>{
    const element={textContent:''};preloadRender({pre},()=>element);return element.textContent;
  };
  const preloadBusy=preloadText({prog:0,label:''});
  if(!preloadBusy.endsWith('0% ・ ')) throw new Error('Unknown original room preload progress presentation');
  const preloadUi={room_preload_busy:preloadBusy.slice(0,-'0% ・ '.length).trimEnd(),
    room_preload_failed:preloadText({error:true}),room_preload_ready:preloadText({terrain:{}})};
  const readyText=/readyBtn.textContent = me\?\.ready \? '([^']+)' : '([^']+)'/.exec(main);
  const loadingText=/pre.label \|\| '([^']+)'/.exec(main);
  const waitingText=/setP\(0\.97, `([^(`]+)\(/.exec(main);
  const readyBody=/const players = lb.clients.filter\([^\n]+\);\n\s*const allReady = [^\n]+;/.exec(main)?.[0];
  const randomText=/class="slot-char dim">([^<]+)</.exec(main);
  const notReadyText=/msg: '([^']+)'/.exec(grabBlock(rooms,'if (!players.every((c) => c.ready))'));
  if(!readyText||!loadingText||!waitingText||!readyBody||!notReadyText||!randomText)throw new Error('Missing original ready/loading UI seams');
  const allReady=new Function('lb',readyBody+'\nreturn allReady;');
  const Hub=new Function('setTimeout','CTRL_MODES','return class {\n'+grabMethod(rooms,'attach')+'\n'+grabMethod(rooms,'leaveRoom')+'\n'+grabMethod(rooms,'maybeLaunch')+'\n};')(()=>{},controls.modes);
  const scenarios=[
    {name:'ready-cancel-load-reconnect',players:true,operations:[
      ['start',1000],['ready',1000,true],['start',1000],['ready',1001,true],
      ['ready',1000,false],['start',1000],['ready',1000,true],['loaded',1000],
      ['start',1001],['start',1000],['server_prepared'],['maybe'],['loaded',1000],
      ['loaded',1002],['close',1001],['maybe'],['claim','test-beta'],
      ['loaded',1004],['loaded',1004],['start',1000],['maybe']]},
    {name:'leave-unloaded-player',players:true,operations:[
      ['ready',1000,true],['ready',1001,true],['start',1000],['server_prepared'],
      ['loaded',1000],['leave',1001],['loaded',1000],['maybe']]},
    {name:'empty-player-set',players:false,operations:[
      ['ready',1000,true],['ready',1001,true],['start',1000],['server_prepared'],
      ['loaded',1000],['loaded',1001],['maybe']]},
  ];
  const programs=[];
  for(const scenario of scenarios) {
    const hub=new Hub(),connections=new Map();
    let launches=0;
    const definitions=scenario.players?
      [[42,'test-alpha','player','STEEL'],[43,'test-beta','player','SWARM'],[44,'test-spectator','spectator','STEEL'],[45,'test-unseated','player',null]]:
      [[42,'test-alpha','spectator','STEEL'],[43,'test-beta','player',null]];
    const room={pin:'1234',hostId:42,phase:'room',config:{teamSize:1,ctrl:controls.defaultMode},battleConfig:{},battle:null,
      clients:new Map(definitions.map(([player,token,mode,side])=>[player,{token,mode,side,connected:true,ready:false,loaded:false,send:()=>{}}])),bots:new Map()};
    Object.assign(hub,{rooms:new Map([[room.pin,room]]),_nextClientId:1000,dropMs:rules.dropMilliseconds,log:()=>{},broadcast:()=>{},osmPayload:()=>null,
      stopBattle:()=>{},_addBotToSide:()=>false,startBattle:target=>{launches++;target.phase='game';target.battle={};}});
    const connect=token=>{
      const connection=hub.attach(()=>{});connections.set(connection.id,connection);
      connection.recv({t:'reattach',token});return connection.id;
    };
    for(const [,token] of definitions)connect(token);
    const snapshot=()=>{
      let loaded=false;
      hub.maybeLaunch.call({startBattle:()=>{loaded=true;}},{...room,phase:'loading'});
      return {phase:room.phase,launches,allReady:allReady({clients:[...room.clients.values()]}),allLoaded:loaded,
        members:[...room.clients].map(([player,client])=>({player,connected:client.connected,ready:client.ready,loaded:client.loaded}))};
    };
    const initial=snapshot(),frames=[];
    for(const operation of scenario.operations) {
      let transport=null;
      if(operation[0]==='ready')connections.get(operation[1]).recv({t:'setReady',ready:operation[2]});
      else if(operation[0]==='start')connections.get(operation[1]).recv({t:'startBattle'});
      else if(operation[0]==='loaded')connections.get(operation[1]).recv({t:'loaded'});
      else if(operation[0]==='leave')connections.get(operation[1]).recv({t:'leaveRoom'});
      else if(operation[0]==='close')connections.get(operation[1]).close();
      else if(operation[0]==='claim')transport=connect(operation[1]);
      else if(operation[0]==='maybe')hub.maybeLaunch(room);
      frames.push({operation,transport,...snapshot()});
    }
    programs.push({name:scenario.name,definitions,initial,frames});
  }
  return {ui:{...preloadUi,room_ready:readyText[2],room_cancel_ready:readyText[1],room_loading:loadingText[1],room_waiting_loaded:waitingText[1],room_not_ready:notReadyText[1],room_random_character:randomText[1]},
    fixtures:{roomLoadingPrograms:programs},inputs:['server/rooms.js','public/js/main.js']};
}
