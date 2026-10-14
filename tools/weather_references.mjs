import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// The original authority runs without the client-global solar schedule.
export async function weatherReferences(d, BattleSim, config, source) {
  const state = await import(pathToFileURL(join(source, 'public/js/weatherState.js')).href);
  const visual = await import(pathToFileURL(join(source, 'public/js/weatherVisuals.js')).href);
  const environment = await readFile(join(source, 'public/js/environment.js'), 'utf8');
  const literal = name => {
    const match = new RegExp(`const ${name} = (\\{[\\s\\S]*?\\n\\});`).exec(environment);
    if (!match) throw new Error(`Original weather palette missing: ${name}`);
    return Function(`return (${match[1]});`)();
  };
  const rules = { surface:state.WEATHER_SURFACE, visuals:visual.WEATHER_FX, times:literal('TIMES'), seasons:literal('SEASONS') };
  const weatherSolar=[], weatherVectors=[], weatherDynamics=[], weatherSurface=[], weatherMath=[], weatherParticles=[], weatherEffects=[], weatherSettlement=[], weatherReload=[], weatherCelestial=[];
  d.setSolarSchedule(null);
  for(const season of Object.keys(d.ENV.seasons))for(const latitude of [-80,-25,0,25,65,80])for(const lunarDay of [0,1,8,15,30,31]) {
    const schedule=d.computeSolarSchedule(season,latitude,0,lunarDay);
    weatherSolar.push({season,latitude,lunarDay,schedule});
  }
  for(const season of Object.keys(d.ENV.seasons))for(const start of Object.keys(d.ENV.times))for(const preset of Object.keys(d.ENV.weathers))
    for(const seed of [0,42,-1123501,0xffffffff])for(const elapsed of [0,.125,30,240,600,1800]) {
      const latitude=seed<0?-25:25;
      const vector=d.weatherVectorAt(season,start,preset,elapsed,seed,latitude);
      weatherVectors.push({season,start,preset,seed,latitude,elapsed,vector});
    }
  const vectors=[null,...Object.values(d.WEATHER_PRESETS),...[0,50,60,74.999,75,75.001,80,90,100].flatMap(value=>
    [25,50,100].map(clouds=>({clouds,fog:value,wind:value,rain:value,sand:value,snow:value,thunder:value,windDirDeg:225})))];
  for(const vector of vectors) {
    weatherDynamics.push({vector:vector||{},previous:{},delta:0,result:d.resolveWeatherDynamics(vector)});
    const dyn=d.resolveWeatherDynamics(vector);
    weatherParticles.push({dyn,result:visual.resolveWeatherVisuals(dyn)});
  }
  for(const previous of [d.resolveWeatherDynamics(d.WEATHER_PRESETS.clear),d.resolveWeatherDynamics(d.WEATHER_PRESETS.snow),
    {...d.resolveWeatherDynamics(d.WEATHER_PRESETS.snow),thawHoldS:.25}, {...d.resolveWeatherDynamics(d.WEATHER_PRESETS.clear),freezeFactor:.79,thawHoldS:0}])
    for(const vector of [d.WEATHER_PRESETS.clear,d.WEATHER_PRESETS.snow,{clouds:100,snow:100}, {clouds:0,snow:90}])
      for(const delta of [0,.125,.25,1,18,18.125,30])
        weatherDynamics.push({previous,vector,delta,result:d.resolveWeatherDynamics(vector,previous,delta)});
  for(const previous of [{},{water:1,snow:1,sand:1},{water:.08,snow:.5,sand:.08},{puddle:1,dune:1}])
    for(const dyn of [{},{effectiveRain:.5,effectiveSnow:.5,effectiveSand:.5,wind:100},{effectiveRain:1,effectiveSnow:1,effectiveSand:1,wind:0}])
      for(const delta of [0,.125,1,30,90,180,600]) {
        const result=state.stepWeatherSurface(previous,dyn,delta);
        weatherSurface.push({previous,dyn,delta,result,ground:d.weatherGroundSlowFactor(result),jump:d.weatherJumpVelocityFactor(result),rate:d.weatherGroundAttackRateFactor(result)});
      }
  for(const wind of [0,75,75.001,100,150])for(const direction of [[1,0],[0,1],[-1,0],[.3,-.4],[0,0]])for(const motion of [[0,0],[.0001,0],[1,0],[0,1],[-1,1]])
    weatherMath.push({type:'wind',wind,direction,motion,result:d.windSpeedFactor(...motion,direction,wind),threshold:d.unbalAltThreshold(wind)});
  for(const dyn of [{},{rain:100,snow:100,sand:100},{effectiveRain:1,effectiveSnow:.5,effectiveSand:.25},
    {rainSlow:.2,rainIntensity:.9,effectiveRain:1,sandSlow:.2,sandIntensity:.9,effectiveSand:1},...weatherDynamics.map(item=>item.result)])
    weatherMath.push({type:'air',dyn,lift:d.weatherFlightLiftFactor(dyn),rate:d.weatherFlightAttackRateFactor(dyn),speed:d.weatherFlightSlowFactor(dyn)});
  for(const fog of [0,.25,1])for(const hour of [0,4,6,9.5,12,18,21,23])for(const lunarDay of [1,8,15,23,30]) {
    const schedule=d.computeSolarSchedule('winter',-25,0,lunarDay);
    weatherMath.push({type:'accuracy',fog,hour,schedule,result:d.weatherAccuracyPenalty(fog,hour,schedule)});
  }
  try {
    for(const season of Object.keys(d.ENV.seasons))for(const latitude of [-65,0,25,65])for(const rotation of [0,Math.PI/3])for(const lunarDay of [1,8,15,30])
      for(const hour of [0,6,12,18,23.5]) {
        const schedule=d.computeSolarSchedule(season,latitude,rotation,lunarDay);d.setSolarSchedule(schedule);
        weatherCelestial.push({schedule,hour,sun:d.sunDirAt(hour),moon:d.lunarMoonDirAt(hour,lunarDay)});
      }
  } finally { d.setSolarSchedule(null); }
  const template=new BattleSim(config);
  for(const rain of [0,75,80,100])for(const frozen of [false,true])for(const weapon of [false,true])for(const reflected of [false,true]) {
    const target={id:1,kind:'tank',side:'STEEL',x:0,z:0,y:0,hp:10000,armor:30,cu:1,freezeUntil:frozen?20:0};
    const sim=Object.assign(Object.create(template),{t:10,over:false,events:[],ents:new Map([[1,target]]),heroes:new Map(),
      curWeatherDyn:d.resolveWeatherDynamics({rain}),_inReflect:reflected,entangleGroups:[],siegeLocked:()=>false,siegeHpFloor:()=>0,_allyBotDmgF:()=>1});
    sim._damage(target,80,null,10,0,weapon?{type:'gun',pen:10}:null);
    weatherSettlement.push({rain,frozen,weapon,reflected,loss:10000-target.hp});
  }
  for(const character of Object.keys(d.CHARACTERS))for(const slot of ['light','heavy'])for(const snow of [0,75,80,100])for(const modifier of [1,.6]) {
    const definition=d.heroWeapon(character,slot,1,true), actor={mods:[{k:'reload',m:modifier,until:20}],buffs:{}};
    const sim=Object.assign(Object.create(template),{t:10,curWeatherDyn:d.resolveWeatherDynamics({snow})});
    weatherReload.push({character,slot,snow,modifier,duration:sim._reloadT(actor,definition)});
  }
  for(const seed of [0,42,-1123501])for(const thunder of [0,.1,.5,.81,1])for(const snow of [0,.5,1]) {
    const entities=[{id:1,kind:'soldier',side:'STEEL',x:0,z:0,y:0}, {id:2,kind:'soldier',side:'SWARM',x:9,z:0,y:0},
      {id:3,kind:'heli',side:'STEEL',x:40,z:0,y:20}, {id:4,kind:'tower',side:'SWARM',x:80,z:0,y:0}].map(e=>
        ({...e,hp:10000,maxHp:10000,sp:0,armor:0,cd:0,buffs:{},mods:[]}));
    const sim=Object.assign(Object.create(template),{weatherSeed:seed,t:0,curWeatherDyn:{effectiveThunder:thunder,effectiveSnow:snow,wind:100},
      weatherSurface:{snow:1},events:[],ents:new Map(entities.map(e=>[e.id,e])),_lightningTimer:0,_lastSnowFreezeStep:undefined,_hgtGrid:null,_wetGrid:null,
      solidResolve:(_e,_x,_z,x,z)=>[x,z], _damage:(target,amount,_by,pen=0)=>{hits.push({id:target.id,amount,pen});target.hp-=amount;}});
    let hits=[];
    const steps=[];
    for(const now of [.125,.25,1,2,3,8,30,31,32,60]) {
      const delta=now-sim.t;sim.t=now;hits=[];sim.events=[];sim._tickWeather(delta);
      steps.push({now,delta,hits:structuredClone(hits),surface:structuredClone(sim.weatherSurface),timer:sim._lightningTimer,
        frozen:entities.map(e=>({id:e.id,until:e.freezeUntil||0,last:e._lastFreezeAt??null})),
        actors:entities.map(e=>({id:e.id,hp:e.hp,x:e.x,z:-e.z,scorched:!!e.lightningScorch})),
        strikes:sim.events.filter(e=>e.e==='lightning_strike').flatMap(e=>e.pts.map(p=>p.id))});
    }
    weatherEffects.push({seed,thunder,snow,steps});
  }
  return {rules,fixtures:{weatherSolar,weatherVectors,weatherDynamics,weatherSurface,weatherMath,weatherParticles,weatherEffects,weatherSettlement,weatherReload,weatherCelestial}};
}
