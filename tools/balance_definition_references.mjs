import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function balanceDefinitionReferences(source) {
  const load=file=>import(pathToFileURL(join(source,file)).href);
  const [{BOT_POLICY},{mulberry32},text,prefsText,{grabMethod},simulationText,gameText]=await Promise.all([
    load('public/js/botPolicy.js'),load('public/js/rng.js'),
    readFile(join(source,'public/js/data.js'),'utf8'),readFile(join(source,'public/js/balancePrefs.js'),'utf8'),
    load('tools/audit_src.mjs'),readFile(join(source,'server/sim.js'),'utf8'),readFile(join(source,'public/js/game.js'),'utf8')]);
  const makePrefs=new Function('localStorage',prefsText.replace(/^export /gm,'')+'\nreturn {balanceMul,upgradeCurveMul,setBalancePref,balancePrefs};');
  const seam='  const q = (v) => Math.round(v * 1000) / 1000;';
  if(text.split(seam).length!==2)throw new Error('Source building calibration seam changed');
  const body=text.replace(/^import .*$/gm,'').replace(/^export \{.*$/gm,'').replace(/^export /gm,'')
    .replace(seam,"  captureBalance(CHARACTERS);\n"+seam);
  const makeData=new Function('BOT_POLICY','balanceMul','upgradeCurveMul','mulberry32','captureBalance',body+
    '\nreturn {CHARACTERS,heroWeapon,heroAbility,heroMobility,charKind,mobMid,rangeMid,heavyMpCost,fireBurstN,fireBurstGap,fanBuildingMaxHits,flightCapS,chaseCapS,chargeF,slotExpectedBuildingDmg,shotTrailS,combatReachM,curveEyeM,curveKneeM,curveR,hyperMaxArcM,BOT_ROLE_FEATS,botRoleOf,botRoleTactic,botBuyOrder,strikeAreaM2,UNITS,ECON,BOSS,SUPER_UPG,heroArmor,superCombatLvl,superDefLvl,upgradeCurveMul};');
  const settlementScope=['UNITS','CHARACTERS','BOSS','heroArmor','upgradeCurveMul','SUPER_UPG','superCombatLvl','superDefLvl','ECON','balanceMul'];
  const normalizedSim=simulationText.replace(/\r\n?/g,'\n');
  const respawnExpression=/const rs = (\(r.base \+ r.perDeath \* playerDeaths\) \* balanceMul\('respawn'\));/.exec(normalizedSim)?.[1];
  if(!respawnExpression)throw new Error('Missing source per-player balance respawn expression');
  const respawnDelay=new Function('r','playerDeaths','balanceMul','return '+respawnExpression+';');
  const makeSettler=new Function(...settlementScope,'return {'+['_applyUpg','_setSuperLvl','_bounty'].map(name=>grabMethod(normalizedSim,name)).join(',')+'};');
  const normalizedGame=gameText.replace(/\r\n?/g,'\n');
  const makeClient=new Function('CHARACTERS','heroWeapon','return {'+['_setChar','_heroDefOf'].map(name=>grabMethod(normalizedGame,name)).join(',')+'};');
  const weaponValues=definition=>Object.fromEntries(['dmg','range','rate','rate0','reload','mag'].map(key=>[key,definition[key]]));
  function settlements(data,prefs) {
    const methods=makeSettler(...settlementScope.map(key=>key==='balanceMul'?prefs.balanceMul:data[key]));
    const state=h=>({hp:h.hp,max_hp:h.maxHp,shield:h.sp,max_shield:h.maxSp,armor:h.armor,alive:!h.dead,
      upgrades:{...h.upg},ammo:{...h.ammo},reload:{...h.reloadUntil}});
    const cases=[];
    for(const character of Object.keys(data.CHARACTERS))for(const dead of [false,true])for(const boss of [false,true]) {
      const makeHero=()=>({ch:character,kind:data.charKind(character),pid:'fixture',dead,hp:dead?0:500,maxHp:900,
        sp:dead?0:80,maxSp:300,armor:20,upg:{hp:0,sp:0,ar:0,super:0},abil:{light:1,heavy:1,def:1,atk:1},
        ammo:{light:1,heavy:2},reloadUntil:{light:90,heavy:100}});
      const context={...methods,_bodies:h=>[h],isBoss:()=>boss,events:[]};
      const hero=makeHero(),initial=state(hero),steps=[];
      for(const [item,level] of [['hp',1],['hp',3],['sp',2],['ar',3],['hp',0]]) {
        hero.upg[item]=level;context._applyUpg(hero,item,data.ECON.UPGRADES[item]);
        steps.push({item,level,result:state(hero)});
      }
      const superHero=makeHero(),superSteps=[];
      for(const level of [0,1,20,100,20,0]) {
        context._setSuperLvl(superHero,level);superSteps.push({level,result:state(superHero)});
      }
      cases.push({character,dead,boss,initial,steps,superSteps});
    }
    return {cases,bounties:Object.fromEntries(Object.keys(data.ECON.BOUNTY).map(kind=>[kind,methods._bounty({kind})])),
      respawns:Object.entries(data.UNITS).filter(([,unit])=>unit.respawn).flatMap(([kind,unit])=>[0,1,7,25].map(deaths=>({kind,deaths,value:respawnDelay(unit.respawn,deaths,prefs.balanceMul)})))};
  }
  function create(saved) {
    const prefs=makePrefs({getItem:()=>JSON.stringify(saved),setItem:()=>{}});
    let baseBuilding;
    const data=makeData(BOT_POLICY,prefs.balanceMul,prefs.upgradeCurveMul,mulberry32,characters=>{
      baseBuilding=Object.fromEntries(Object.entries(characters).map(([id,ch])=>[id,
        Object.fromEntries(['light','heavy'].map(slot=>[slot,ch[slot]?.vs?.building??1]))]));
    });
    return {data,prefs,baseBuilding};
  }
  const baseline=create({});
  const rules={baseBuilding:baseline.baseBuilding,curveEye:baseline.data.curveEyeM(),hyperMaxArc:baseline.data.hyperMaxArcM(),singleStrikeArea:baseline.data.strikeAreaM2({type:'gun'}),
    staticRoleFeatures:Object.fromEntries(Object.keys(baseline.data.CHARACTERS).map(ch=>[ch,Object.fromEntries(['dur','armor','aid'].map(key=>[key,baseline.data.BOT_ROLE_FEATS[key].raw(ch)]))])),
    rangeMid:Object.fromEntries(['light','heavy'].map(slot=>[slot,baseline.data.rangeMid(slot)])),
    expectedBuildingDamage:Object.fromEntries(['light','heavy'].map(slot=>[slot,baseline.data.slotExpectedBuildingDmg(slot)]))};
  const programs=[];
  const starts=[{},
    {stat_speed:2.3,stat_sight:.2,stat_rate:3.1,stat_cd:.2,stat_dmg:1.7,stat_range:2.4,stat_mpCost:.4},
    {upg_lw_start:10,upg_lw_end:.1,upg_hw_start:.1,upg_hw_end:10,stat_sight:3.7},
    {upg_hp_start:3.4,upg_hp_end:.1,upg_sp_start:.2,upg_sp_end:4.3,upg_ar_start:2.4,upg_ar_end:.3,upg_ch_start:.1,upg_ch_end:2.5}];
  for(const saved of starts) {
    const {data,prefs}=create(saved),frames=[];
    const client={...makeClient(data.CHARACTERS,data.heroWeapon),ch:'t01',side:'STEEL',abil:{light:1,heavy:1},wdef:{},wstate:{},_wdefCache:new Map()};
    client._setChar(client.ch);
    const operations=[null,['stat_speed',.3],['stat_sight',.7],['stat_rate',.4],['stat_cd',3.2],['stat_dmg',2.6],['upg_lw_end',3.4],['upg_hp_end',.1],['stat_bounty',2.3],['stat_respawn',.3]];
    for(const operation of operations) {
      if(operation)prefs.setBalancePref(...operation);
      if(operation?.[0]==='upg_lw_end'){client.abil.light=4;client._setChar(client.ch,true);}
      const rows=[];
      for(const ch of Object.keys(data.CHARACTERS))for(const level of [1,4,5.95,16]) {
        const weapons={};
        for(const slot of ['light','heavy']) {
          const definition=data.heroWeapon(ch,slot,level);
          weapons[slot]={dmg:definition.dmg,range:definition.range,rate:definition.rate,rate0:definition.rate0,reload:definition.reload,
            building:definition.vs.building,burstCount:data.fireBurstN(definition),burstGap:data.fireBurstGap(definition),
            fanMaxBuildingHits:data.fanBuildingMaxHits(definition),flightCap:data.flightCapS(definition),fuel:data.chaseCapS(definition),
            heavyMp:slot==='heavy'?data.heavyMpCost(definition):0};
        }
        rows.push({ch,level,weapons,abilities:Object.fromEntries(['def','atk'].map(slot=>{
          const a=data.heroAbility(ch,slot,level);return [slot,{dmg:a.dmg,heal:a.heal,cd:a.cd,mp:a.mp,range:a.range}];
        })),speed:data.heroMobility(data.charKind(ch),data.CHARACTERS[ch].mods),
          flySpeed:data.heroMobility(data.charKind(ch),data.CHARACTERS[ch].mods,true)});
      }
      frames.push({operation,rows,charge:[0,1,2,3,10,15].map(level=>({level,value:data.chargeF(level)})),
        shotTrailSeconds:data.shotTrailS(),combatReach:data.combatReachM(),viewCurve:{knee:data.curveKneeM(),inverse:1/(2*data.curveR())},
        botProfiles:Object.fromEntries(Object.keys(data.CHARACTERS).map(ch=>{const role=data.botRoleOf(ch);return [ch,{role,tactic:data.botRoleTactic(undefined,role),buy:data.botBuyOrder(role)}];})),
        settlement:settlements(data,prefs),clientWeapons:{lightLevel:client.abil.light,heavyLevel:client.abil.heavy,
          own:Object.fromEntries(['light','heavy'].map(slot=>[slot,weaponValues(client.wdef[slot])])),
          other:Object.fromEntries(['light','heavy'].map(slot=>[slot,weaponValues(client._heroDefOf(client.ch,slot))]))}});
    }
    programs.push({saved,frames});
  }
  return {rules,fixtures:{balanceDefinitionPrograms:programs}};
}
