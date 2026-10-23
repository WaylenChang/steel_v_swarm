import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function roomRosterReferences(source,d,variant) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const sim=(await readFile(join(source,'server/sim.js'),'utf8')).replace(/\r\n?/g,'\n');
  const rooms=(await readFile(join(source,'server/rooms.js'),'utf8')).replace(/\r\n?/g,'\n');
  const main=(await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n');
  const namePrefix=/\|\| `([^`$]*)\$\{room.nextBotId\}`/.exec(rooms);
  const addText=/add.textContent = '([^']+)';\n\s*add.onclick = [^\n]*t: 'addBot'/.exec(main);
  const removeText=/slotX\('([^']+)', \(\) => app.net\?\.send\(\{ t: 'removeBot'/.exec(main);
  if(!namePrefix||!addText||!removeText)throw new Error('Missing original bot names or room UI');
  const method=grabMethod(sim,'addHero');
  const end=method.indexOf('const kind = heroKindOf');
  if(end<0)throw new Error('Missing original hero assignment boundary');
  const body=method.slice(method.indexOf('{')+1,end);
  let draw=0,draws=0;
  const math=Object.create(Math);math.random=()=>{draws++;return draw;};
  const choose=new Function('CHARACTERS','charsOf','isSuperSide','Math',
    'return function(side,pid,ch){'+body+'\nreturn {side,pid,ch};};')(d.CHARACTERS,d.charsOf,d.isSuperSide,math);
  const heroPools=Object.fromEntries(['SWARM','STEEL',d.SUPER_SIDE].map(side=>[side,d.charsOf(side)]));
  const fixtures=[];
  const capture=(name,side,requested,previous,value)=>{
    draw=value;draws=0;
    const heroes=new Map(previous.map((hero,index)=>[index+1,{side:hero.side,ch:hero.character}]));
    const result=choose.call({heroes},side,1000,requested);
    fixtures.push({name,side,requested,previous,draw:value,draws,result:result.ch});
  };
  for(const [side,pool]of Object.entries(heroPools)) {
    for(const character of pool)capture('explicit-repetition',side,character,[{side,character}],.37);
    const full=pool.map(character=>({side,character}));
    const other=side==='STEEL'?'SWARM':'STEEL';
    const merc=Object.keys(d.CHARACTERS).filter(character=>d.CHARACTERS[character].side==='MERC');
    for(const value of [0,.2,.5,.999999999]) {
      capture('initial-random',side,'',[],value);
      capture('unused-same-side',side,'',full.slice(0,3),value);
      capture('exhausted-pool-fallback',side,'',full,value);
      capture('other-faction-mercenaries',side,'',merc.map(character=>({side:other,character})),value);
      capture('unknown-request',side,'missing-character',[],value);
      if(side!==d.SUPER_SIDE)capture('wrong-faction-request',side,d.charsOf(other).find(character=>d.CHARACTERS[character].side===other),[],value);
    }
  }
  const Hub=new Function('BOT_NAMES','CHARACTERS','SIDES','setTimeout','return class {\n'+
    ['attach','_sideCount','_addBotToSide','leaveRoom'].map(name=>grabMethod(rooms,name)).join('\n')+'\n};')(d.BOT_NAMES,d.CHARACTERS,d.SIDES,()=>{});
  const merc=Object.keys(d.CHARACTERS).find(character=>d.CHARACTERS[character].side==='MERC');
  const programs=[];
  const cases=[
    {name:'capacity-picks-and-phase',capacity:2,sides:['STEEL','SWARM'],operations:[
      ['add',1001,'SWARM'],['add',1000,'SWARM'],['add',1000,'SWARM'],['add',1000,'STEEL'],
      ['character',1001,-1,merc],['character',1000,-1,d.charsOf('STEEL').find(id=>d.CHARACTERS[id].side==='STEEL')],
      ['character',1000,-1,merc],['character',1000,-2,merc],['character',1000,-1,''],
      ['character',1000,-1,'missing-character'],['remove',1000,-1],['add',1000,'SWARM'],['add',1000,'SUPER'],
      ['phase','loading'],['remove',1000,-2],['character',1000,-2,''],['add',1000,'STEEL'],
      ['phase','game'],['remove',1000,-2],['phase','over'],['remove',1000,-2]]},
    {name:'names-exhaustion-and-reuse',capacity:5,sides:[''],operations:[
      ...Array.from({length:5},()=>['add',1000,'SWARM']),...Array.from({length:5},()=>['add',1000,'STEEL']),
      ['remove',1000,-1],['add',1000,'SWARM'],['remove',1000,-9],['add',1000,'STEEL']]},
    {name:'host-seat-transfer',capacity:1,sides:['STEEL','SWARM'],operations:[
      ['add',1000,'STEEL'],['leave',1000],['add',1000,'STEEL'],['add',1001,'STEEL'],['character',1001,-1,merc]]},
  ];
  for(const item of cases) {
    const hub=new Hub(),connections=new Map();
    const room={pin:'1234',hostId:42,phase:'room',config:{teamSize:item.capacity},battleConfig:null,battle:null,
      clients:new Map(item.sides.map((side,index)=>[42+index,{side,token:'test-'+index,connected:true,mode:'player',send:()=>{}}])),
      bots:new Map(),nextBotId:0};
    Object.assign(hub,{rooms:new Map([[room.pin,room]]),_nextClientId:1000,log:()=>{},broadcast:()=>{},osmPayload:()=>null,stopBattle:()=>{}});
    for(let i=0;i<item.sides.length;i++) {
      const connection=hub.attach(()=>{});connections.set(connection.id,connection);
      connection.recv({t:'reattach',token:'test-'+i});
    }
    const snapshot=()=>({host:room.hostId,nextBot:room.nextBotId,
      counts:Object.fromEntries(['SWARM','STEEL','SUPER'].map(side=>[side,hub._sideCount(room,side)])),
      bots:[...room.bots].map(([id,bot])=>({player:-Number(id.slice(1)),side:bot.side,name:bot.name,character:bot.ch||''}))});
    const initial=snapshot(),frames=[];
    for(const operation of item.operations) {
      const [kind,transport,value,character]=operation;
      if(kind==='phase')room.phase=transport;
      else if(kind==='leave')connections.get(transport).recv({t:'leaveRoom'});
      else if(kind==='add')connections.get(transport).recv({t:'addBot',side:value});
      else if(kind==='remove')connections.get(transport).recv({t:'removeBot',id:'b'+(-value)});
      else if(kind==='character')connections.get(transport).recv({t:'setBotChar',id:'b'+(-value),ch:character||null});
      frames.push({operation,...snapshot()});
    }
    programs.push({...item,initial,frames});
  }
  const {BotBrain}=await import(pathToFileURL(join(source,'server/bots.js')).href);
  const {mulberry32}=await import(pathToFileURL(join(source,'public/js/rng.js')).href);
  const assign=new Function('CHARACTERS','charsOf','isSuperSide',
    'return function(side,pid,ch){'+body+'\nreturn {side,pid,ch};};')(d.CHARACTERS,d.charsOf,d.isSuperSide);
  const deployments=[];
  for(const randomHumans of [false,true]) {
    const roster=[{peer:42,side:'STEEL',character:randomHumans?'':merc,bot:false},
      {peer:43,side:'SWARM',character:merc,bot:false},
      ...Array.from({length:8},(_,i)=>({peer:-i-1,side:i%2?'SWARM':'STEEL',character:i===0||i===2?merc:'',bot:true}))];
    let count=0;
    const heroes=[],brains=[],random=mulberry32(42),saved=Math.random;
    class AssignmentSim {
      constructor() {this.heroes=new Map();this.lanes=variant.lanes;}
      addHero(side,pid,ch) {
        const hero=assign.call(this,side,pid,ch);this.heroes.set(pid,hero);
        heroes.push({peer:typeof pid==='string'?-Number(pid.slice(1)):pid,side,character:hero.ch,draws:count});
        return hero;
      }
      fieldPayload() {return {};}
    }
    class AssignmentBrain extends BotBrain {
      constructor(...args) {
        super(...args);
        brains.push({peer:-Number(this.pid.slice(1)),lane:this.lane,alt:this.alt,jitter:[this.jitter[0],-this.jitter[1]],draws:count});
      }
    }
    const LaunchHub=new Function('BattleSim','BotBrain','setInterval','GAME','return class {\n'+grabMethod(rooms,'startBattle')+'\n};')(AssignmentSim,AssignmentBrain,()=>1,d.GAME);
    const hub=new LaunchHub(),room={battle:null,battleConfig:variant.config,pin:'fixture',config:{botDiff:d.DEFAULT_BOT_DIFF},
      clients:new Map(roster.filter(player=>!player.bot).map(player=>[player.peer,{mode:'player',side:player.side,ch:player.character,send:()=>{}}])),
      bots:new Map(roster.filter(player=>player.bot).map(player=>['b'+(-player.peer),{side:player.side,ch:player.character}]))};
    Object.assign(hub,{log:()=>{},broadcast:()=>{}});
    let next;
    try {
      Math.random=()=>{count++;return random();};
      hub.startBattle(room);
      if(!room.battle||room.phase!=='game'||heroes.length!==roster.length||brains.length!==room.bots.size)
        throw new Error('Original room hero/brain constructor capture did not complete');
      next=random();
    } finally {Math.random=saved;}
    deployments.push({roster,heroes,brains,draws:count,next,teamSize:variant.hero_spawns.STEEL.length});
  }
  return {rules:{heroPools,botNamePrefix:namePrefix[1]},ui:{room_add_bot:addText[1],room_remove_bot:removeText[1]},
    fixtures:{roomHeroSelection:fixtures,roomBotPrograms:programs,roomHeroDeployment:deployments},inputs:['server/sim.js','server/rooms.js','server/bots.js','public/js/data.js','public/js/main.js','public/js/rng.js']};
}
