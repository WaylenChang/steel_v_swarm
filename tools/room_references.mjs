import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {roomLoadingReferences} from './room_loading_references.mjs';
import {roomRosterReferences} from './room_roster_references.mjs';
import {roomMemberReferences} from './room_member_references.mjs';
import {roomAdmissionReferences} from './room_admission_references.mjs';
import {roomRematchReferences} from './room_rematch_references.mjs';
import {roomRecoveryReferences} from './room_recovery_references.mjs';
import {roomMetadataReferences} from './room_metadata_references.mjs';
import {deploymentReferences} from './deployment_references.mjs';
import {quickRestartReferences} from './quick_restart_references.mjs';
import {fatalReferences} from './fatal_references.mjs';

export async function roomReferences(source,controls,d,variant,campaign) {
  const {grabMethod,grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const rooms=(await readFile(join(source,'server/rooms.js'),'utf8')).replace(/\r\n?/g,'\n');
  const net=(await readFile(join(source,'public/js/net.js'),'utf8')).replace(/\r\n?/g,'\n');
  const duration=key=>{
    const match=new RegExp('this\\.'+key+' = opts\\.'+key+' \\?\\? ([^;]+);').exec(rooms);
    if(!match||!/^[\d\s*+./()]+$/.test(match[1]))throw new Error('Missing original room duration: '+key);
    return new Function('return ('+match[1]+');')();
  };
  const retry=/Math\.min\((\d+), (\d+) \* 2 \*\* Math\.min\(this\._fails, (\d+)\)\)/.exec(net);
  if(!retry)throw new Error('Missing original connection retry schedule');
  const rules={dropMilliseconds:duration('dropMs'),noHumanMilliseconds:duration('noHumanMs'),
    retryMaximumMilliseconds:Number(retry[1]),retryBaseMilliseconds:Number(retry[2]),retryExponentMaximum:Number(retry[3])};
  const retryDelays=[];
  const Retry=new Function('setTimeout','clearTimeout','return class {\n'+grabMethod(net,'_later')+'\n};')(
    (_callback,delay)=>{retryDelays.push(delay);return retryDelays.length;},()=>{});
  const connection=new Retry();
  connection._fails=0;
  for(let i=0;i<12;i++)connection._later();
  connection._dead=true;
  connection._later();
  const programs=[];
  for(const phase of ['room','loading','game','over'])for(const flow of ['hold','redrop','leave','takeover']) {
    let now=0,closing=0,timerOrder=0;
    const timers=[],connections=new Map();
    const enqueue=(callback,delay)=>{timers.push({callback,at:now+delay,transport:closing,order:timerOrder++});};
    const Hub=new Function('setTimeout','CTRL_MODES','return class {\n'+grabMethod(rooms,'attach')+'\n'+grabMethod(rooms,'leaveRoom')+'\n};')(enqueue,controls.modes);
    const hub=new Hub();
    Object.assign(hub,{rooms:new Map(),_nextClientId:1000,dropMs:rules.dropMilliseconds,log:()=>{},broadcast:()=>{},osmPayload:()=>null,stopBattle:()=>{}});
    const room={pin:'1234',hostId:42,phase,config:{ctrl:controls.defaultMode},battleConfig:null,clients:new Map([
      [42,{token:'test-alpha',connected:true,send:()=>{}}],[43,{token:'test-beta',connected:true,send:()=>{}}]])};
    hub.rooms.set(room.pin,room);
    const connect=token=>{
      const send=()=>{},connection=hub.attach(send);
      connection.recv({t:'reattach',token});
      connections.set(connection.id,{connection,send});
      return {transport:connection.id,success:[...room.clients.values()].some(client=>client.send===send&&client.connected)};
    };
    connect('test-alpha');connect('test-beta');
    const snapshot=()=>({host:room.clients.size?room.hostId:0,ctrl:room.config.ctrl,members:[...room.clients].map(([player,client])=>({player,connected:client.connected}))});
    const initial=snapshot(),frames=[];
    const apply=operation=>{
      const expired=[];let result=null;
      if(operation[0]==='close') {
        closing=operation[1];connections.get(closing).connection.close();closing=0;
      } else if(operation[0]==='leave') {
        connections.get(operation[1]).connection.recv({t:'leaveRoom'});
      } else if(operation[0]==='mode') {
        connections.get(operation[1]).connection.recv({t:'setRoomConfig',ctrl:operation[2]});
      } else if(operation[0]==='claim')result=connect(operation[1]);
      else if(operation[0]==='wait') {
        now+=operation[1];
        timers.sort((a,b)=>a.at-b.at||a.order-b.order);
        while(timers.length&&timers[0].at<=now) {
          const timer=timers.shift();expired.push(timer.transport);timer.callback();
        }
      }
      frames.push({operation,result,expired,...snapshot()});
    };
    const firstMode=controls.modeKeys.find(key=>key!==controls.defaultMode);
    apply(['mode',1001,firstMode]); // Non-host requests do not change room controls.
    apply(['mode',1000,'invalid']);apply(['mode',1000,firstMode]);
    if(flow==='takeover') {
      apply(['claim','test-alpha']);apply(['close',1000]);
      apply(['mode',1002,controls.defaultMode]);apply(['leave',1002]);
      apply(['claim','test-alpha']);apply(['mode',1001,firstMode]);apply(['leave',1001]);
    } else if(flow==='leave') {
      apply(['leave',1000]);apply(['close',1000]);
      apply(['claim','test-alpha']);apply(['mode',1001,controls.defaultMode]);apply(['leave',1001]);
    } else {
      apply(['close',1000]);
      apply(['wait',rules.dropMilliseconds/2]);
      apply(['claim','test-alpha']);
      apply(['mode',1002,controls.defaultMode]);
      apply(['close',1000]); // A late close belongs to the replaced connection.
      if(flow==='redrop')apply(['close',1002]);
      apply(['wait',rules.dropMilliseconds/2]);
      if(flow==='hold')apply(['close',1002]);
      apply(['wait',rules.dropMilliseconds]);
      apply(['claim','test-alpha']);
      apply(['close',1001]);
      apply(['wait',rules.dropMilliseconds]);
    }
    programs.push({phase,flow,initial,frames});
  }
  const noHumanPrograms=[];
  const NoHumanHub=new Function('return class {\n'+grabMethod(rooms,'_endAbandoned')+'\n};')();
  const noHumanGuard='if (this.noHumanMs > 0)';
  const observe=new Function('room','now',noHumanGuard+grabBlock(rooms,noHumanGuard));
  for(const duration of [rules.noHumanMilliseconds,0,-1]) {
    const hub=new NoHumanHub(),room={pin:'1234',noHumanAt:0,clients:new Map([
      [42,{connected:true,mode:'player'}],[43,{connected:true,mode:'spectator'}]])};
    Object.assign(hub,{rooms:new Map([[room.pin,room]]),noHumanMs:duration,log:()=>{},stopBattle:()=>{hub.ended=true;}});
    const frames=[],tick=now=>{
      observe.call(hub,room,now);
      frames.push({operation:['tick',now],since:room.noHumanAt,abandoned:!!hub.ended});
    },connected=(id,value)=>{
      room.clients.get(id).connected=value;
      frames.push({operation:['connected',id,value],since:room.noHumanAt,abandoned:!!hub.ended});
    };
    const limit=rules.noHumanMilliseconds;
    tick(1000);connected(42,false);tick(1125); // A connected spectator keeps the room alive.
    connected(43,false);tick(1250);tick(1250+limit-1);
    connected(43,true);tick(1250+limit);connected(43,false);
    tick(1375+limit);tick(1375+limit*2-1);tick(1375+limit*2);
    noHumanPrograms.push({duration,frames});
  }
  const loading=await roomLoadingReferences(source,controls,rules);
  const OwnerHub=new Function('setTimeout','clearInterval','return class {\n'+
    ['attach','leaveRoom','stopBattle'].map(name=>grabMethod(rooms,name)).join('\n')+'\n};');
  const ownerPrograms=[];
  for(const flow of ['leave','expire']) {
    const timers=[];
    const Hub=OwnerHub(callback=>{timers.push(callback);},()=>{}),hub=new Hub();
    const owner={id:991,pid:42,clones:[{id:992}]},summon={id:993,ownerPid:42},hologram={id:994,ownerPid:42};
    const room={pin:'owner-fixture',phase:'game',hostId:42,config:{ctrl:controls.defaultMode},battleConfig:null,
      clients:new Map([[42,{side:'STEEL',mode:'player',token:'owner',connected:true,send:()=>{}}],
        [43,{side:null,mode:'spectator',token:'observer',connected:true,send:()=>{}}]]),bots:new Map(),
      battle:{heroes:new Map([[42,owner]]),ents:new Map([owner,...owner.clones,summon,hologram].map(actor=>[actor.id,actor])),
        autonomousSummons:[summon],hologramDecoys:[hologram]},botBrains:[]};
    Object.assign(hub,{rooms:new Map([[room.pin,room]]),_nextClientId:1000,dropMs:rules.dropMilliseconds,log:()=>{},broadcast:()=>{},osmPayload:()=>null});
    const ownerConnection=hub.attach(()=>{}),observerConnection=hub.attach(()=>{});
    ownerConnection.recv({t:'reattach',token:'owner'});observerConnection.recv({t:'reattach',token:'observer'});
    const snapshot=operation=>({operation,members:[...room.clients.keys()],battleAlive:!!room.battle,
      actors:room.battle?[...room.battle.ents.keys()]:[],ownerAlive:room.battle?.heroes.get(42)===owner,
      clones:room.battle?.heroes.get(42)?.clones.length||0,summons:room.battle?.autonomousSummons.length||0,holograms:room.battle?.hologramDecoys.length||0});
    const frames=[snapshot('initial')];
    if(flow==='leave')ownerConnection.recv({t:'leaveRoom'});
    else {ownerConnection.close();frames.push(snapshot('close'));timers.shift()();}
    frames.push(snapshot(flow));
    observerConnection.recv({t:'leaveRoom'});frames.push(snapshot('last-leave'));
    ownerPrograms.push({flow,frames});
  }
  const roster=await roomRosterReferences(source,d,variant);
  const members=await roomMemberReferences(source,d);
  const admission=await roomAdmissionReferences(source,d);
  const rematch=await roomRematchReferences(source,controls);
  const recovery=await roomRecoveryReferences(source);
  const metadata=await roomMetadataReferences(source,d,controls);
  const deployment=await deploymentReferences(source,d);
  const quick=await quickRestartReferences(source,d,controls,variant,campaign);
  const fatal=await fatalReferences(source);
  return {rules:{...rules,...roster.rules,...recovery.rules,...metadata.rules,...deployment.rules,...fatal.rules,ui:{...loading.ui,...roster.ui,...members.ui,...admission.ui,...rematch.ui,...metadata.ui,...deployment.ui,...quick.ui,...fatal.ui}},fixtures:{roomSeatPrograms:programs,roomRetryDelays:retryDelays,roomNoHumanPrograms:noHumanPrograms,roomOwnerPrograms:ownerPrograms,...loading.fixtures,...roster.fixtures,...members.fixtures,...admission.fixtures,...rematch.fixtures,...recovery.fixtures,...metadata.fixtures,...deployment.fixtures,...quick.fixtures,...fatal.fixtures},inputs:['server/rooms.js','public/js/net.js',...loading.inputs,...roster.inputs,...members.inputs,...admission.inputs,...rematch.inputs,...recovery.inputs,...metadata.inputs,...deployment.inputs,...quick.inputs,...fatal.inputs]};
}
