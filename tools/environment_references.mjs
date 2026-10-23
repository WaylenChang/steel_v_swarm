import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function environmentReferences(d, BattleSim, config, source, gameSource) {
  const {readSrc,grabFn,grabMethod,grabBlock}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const terrainText=readSrc('public','js','terrain.js'),biomeText=readSrc('public','js','biomes.js'),mainText=readSrc('public','js','main.js');
  const classifier=new Function('WATER',`${grabFn(biomeText,'terrainEnvCode')}\nreturn terrainEnvCode;`)(d.WATER);
  const bandMask = new Function(`${grabFn(readSrc('public','js','ground.js'),'makeBandMask')}\nreturn makeBandMask;`)();
  const environmentBorderMasks = [];
  const masks = [
    {cell:24,halfWidthMax:9,grid:{}},
    {cell:24,halfWidthMax:9,grid:{'0,0':[{x0:-10,z0:0,x1:60,z1:0,hw:9}]}},
    {cell:24,halfWidthMax:60,grid:{'-2,-1':[{x0:-32,z0:-16,x1:-32,z1:-16,hw:60}]}},
    {cell:24,halfWidthMax:9,grid:{'-1,0':[{x0:-30,z0:1,x1:30,z1:31,hw:3}],
      '0,1':[{x0:0,z0:24,x1:0,z1:24,hw:0}]}}];
  for (const profile of masks) {
    const query = bandMask(new Map(Object.entries(profile.grid)),profile.cell,profile.halfWidthMax);
    for (const x of [-96,-64,-32,-24.001,-24,-9,0,9,24,48,60,69,69.001,96])
      for (const z of [-80,-24,-16,-9,-3,0,1,3,9,9.001,24,31,60])
        environmentBorderMasks.push({profile,x,z,result:query(x,z)});
  }
  const distance=new Function(`${grabFn(terrainText,'distToSegs')}\nreturn distToSegs;`)();
  const sample=new Function('field','x','z','N','minX','maxX','minZ','maxZ',grabBlock(terrainText,'function sampleField('));
  let frozen=false;
  const scope={...d,terrainEnvCode:classifier,isWeatherFrozen:()=>frozen};
  const method=name=>new Function(...Object.keys(scope),`return function ${grabMethod(gameSource.replace(/\r\n/g,'\n'),name).trim().slice(name.length)}`)(...Object.values(scope));
  const envAt=method('_envAt'),slow=method('_terrainSlowF'),jump=method('_terrainJumpVelocityF'),zone=method('_zoneSlow');
  const environmentHeights=[],environmentDryBands=[],environmentTriggers=[],environmentStates=[],environmentTides=[],environmentFire=[],environmentBurn=[],environmentIce=[],environmentWetGrid=[],environmentFloods=[];
  const bounds={minX:-20,maxX:40,minZ:-30,maxZ:50};
  for(const grid of [2,3,5]) {
    const heights=new Float32Array(Array.from({length:grid**2},(_,i)=>Math.sin(i*.73)*12+i*.31));
    for(const x of [-100,-20,-5,10,25,40,100])for(const z of [-100,-30,-10,0,20,50,100])
      environmentHeights.push({bounds,grid,heights:Array.from(heights),x,z,result:sample(heights,x,z,grid,bounds.minX,bounds.maxX,bounds.minZ,bounds.maxZ)});
  }
  for(const segments of [[],[[0,0,100,0]],[[0,0,0,0]],[[0,0,100,0],[100,0,100,100]]])for(const radius of [0,16])
    for(const x of [-20,0,50,100,120])for(const z of [-16,0,16,16.001,40])
      environmentDryBands.push({profile:{segments,radius},x,z,result:distance(x,z,segments)<=radius});
  for(const ground of [0,1,2])for(const waterY of [null,.3])for(const foot of [-30,0,.3,2.5,30])for(const body of [0,8,26])for(const ice of [false,true])
    environmentTriggers.push({ground,waterY,foot,body,frozen:ice,result:d.envTrigger(ground,waterY,foot,body,ice)});
  for(const height of [-10,.3,1,3])for(const color of [null,[30,30,70],[80,90,80],[100,60,30]])for(const dry of [false,true])
    for(const foot of [-15,0,.3,2.5,8,30])for(const body of [8,26])for(const flying of [false,true])for(const ice of [false,true])for(const border of [false,true]) {
      frozen=ice;
      const terrain={waterY:.3,heightAt:()=>height,sampleColor:()=>color,inDryBand:()=>dry,inBorderBand:()=>border};
      const context={terrain,pos:{x:0,z:0,y:foot},selfH:body,_flying:()=>flying,_surf:()=>height,_env:null,floods:[]};
      context._env=envAt.call(context);
      environmentStates.push({height,color:color||[],dry,border,waterY:.3,foot,body,flying,frozen:ice,surface:height,
        ground:classifier(terrain,0,0),state:context._env,speed:slow.call(context),jump:jump.call(context)});
    }
  for(const hour of [0,6,12,18,24])for(const lunarDay of [0,1,8,15,23,30,31])for(const marine of [false,true])
    environmentTides.push({hour,lunarDay,marine,result:d.tideLevelAt(hour,lunarDay,marine)});
  for(const rain of [0,55,75,100])for(const snow of [0,50,75,100])for(const wind of [0,65,80,100]) {
    const dynamics={rain,snow,wind};environmentFire.push({dynamics,result:d.fireDotMul(dynamics)});
  }
  const template=new BattleSim(config);
  const surfaceText=mainText.slice(mainText.indexOf('terrain.surfaceAt ='),mainText.indexOf('terrain.ceilingAt ='));
  const ceilingText=mainText.slice(mainText.indexOf('terrain.ceilingAt ='));
  const marker="if (typeof isWeatherFrozen === 'function' && isWeatherFrozen() && terrain.waterY != null)";
  const surfaceBlock=grabBlock(surfaceText,marker),ceilingBlock=grabBlock(ceilingText,marker);
  const step=/const DECK_STEP = ([\d.]+)/.exec(mainText);if(!step)throw new Error('Original ice deck-step seam missing');
  const iceScope={WATER:d.WATER,DECK_STEP:Number(step[1]),isWeatherFrozen:()=>frozen,terrainEnvCode:()=>iceGround};
  const iceSurface=new Function(...Object.keys(iceScope),'s','curY','terrain',`const x=0,z=0; ${marker} ${surfaceBlock}\nreturn s;`);
  const iceCeiling=new Function(...Object.keys(iceScope),'c','curY','terrain',`const x=0,z=0; ${marker} ${ceilingBlock}\nreturn c;`);
  let iceGround=0;
  for(const ground of [0,1,2])for(const foot of [-15,-2,.3,2.5,10])for(const surface of [-10,0,5])for(const ceiling of [null,-1,10])for(const ice of [false,true]) {
    frozen=ice;iceGround=ground;const terrain={waterY:.3};
    environmentIce.push({ground,foot,surface,ceiling,frozen:ice,waterY:.3,
      floor:iceSurface(...Object.values(iceScope),surface,foot,terrain),ceilingResult:iceCeiling(...Object.values(iceScope),ceiling,foot,terrain)});
  }
  for(const grid of [{minX:-20,minZ:-30,cell:20,cols:3,rows:2,data:'012210'},
    {minX:-20,minZ:-30,cell:20,cols:3,rows:2,data:'a12b10'}, {minX:0,minZ:0,cell:0,cols:2,rows:2,data:'1212'},
    {minX:0,minZ:0,cell:20,cols:3,rows:2,data:'012'}])for(const x of [-21,-20,-.001,0,20,39.999,40])for(const nativeZ of [-31,-30,-10,0,10,30,31]) {
    const sim=Object.assign(Object.create(template),{_wetGrid:null});sim._ingestWorldWet({wet:grid});
    environmentWetGrid.push({grid,x,z:nativeZ,result:sim._wetAt(x,-nativeZ)});
  }
  for(const hp of [0,100,1000])for(const shield of [0,30,500])for(const maximumShield of [0,500])for(const amount of [-20,0,1,80,2000])
    for(const modifier of [1,.4])for(const protection of ['none','invulnerable','garrison','iframe','phase']) {
      const unit={id:1,pid:1,hero:true,ch:'t05',kind:'robot',side:'STEEL',x:0,z:0,y:0,hp,sp:shield,maxHp:1000,maxSp:maximumShield,
        mods:[{k:'dmgTaken',m:modifier,until:20}],buffs:{},inv:protection==='invulnerable',gar:protection==='garrison',
        invUntil:protection==='iframe'?20:0,phaseUntil:protection==='phase'?20:0,bleed:{pid:2}};
      const killer={id:2,pid:2,hero:true,kind:'robot',ch:'t05',side:'SWARM'};
      const deaths=[];
      const sim=Object.assign(Object.create(template),{t:10,over:false,events:[],heroes:new Map([[1,unit],[2,killer]]),
        _kill:(target,by)=>deaths.push({id:target.id,killer:by?.id||0})});
      sim._fireBurn(unit,amount);
      environmentBurn.push({hp,shield,maximumShield,amount,modifier,protection,
        result:{hp:unit.hp,shield:unit.sp,damaged:unit.lastHitAt??null,deaths}});
    }
  frozen=false;
  for(const flying of [false,true])for(const airborne of [false,true])for(const x of [0,10,10.001])for(const modifier of [null,.05,.8]) {
    const flood={x:0,z:0,r:10,...(modifier==null?{}:{slow:modifier})};
    const context={pos:{x,z:0},_flying:()=>flying,_env:{air:airborne,ground:0,code:0},floods:[flood],_floodWarnAt:Infinity};
    environmentFloods.push({flying,airborne,x,floods:[{x:0,z:0,radius:10,...(modifier==null?{}:{slow:modifier})}],
      active:!flying&&!airborne&&x<=10,speed:zone.call(context),jump:jump.call(context)});
  }
  return {environmentHeights,environmentDryBands,environmentBorderMasks,environmentTriggers,environmentStates,environmentTides,environmentFire,environmentBurn,environmentIce,environmentWetGrid,environmentFloods};
}
