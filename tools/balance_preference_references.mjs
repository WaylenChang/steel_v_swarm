import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function balancePreferenceReferences(source) {
  const text=(await readFile(join(source,'public/js/balancePrefs.js'),'utf8')).replace(/\r\n?/g,'\n');
  // Isolated instances must not change data.js's imported factory balance.
  const factory=new Function('localStorage',text.replace(/^export /gm,'')+'\nreturn {BALANCE_KNOBS,balancePref,balanceMul,upgradeCurveMul,balancePrefs,setBalancePref,resetBalancePrefs,balancePrefsDefault,onBalanceChange};');
  const scalar=expression=>{const match=expression.exec(text);if(!match)throw new Error('Missing source balance preference seam: '+expression);return Number(match[1]);};
  const original=factory(undefined);
  const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const panel=grabFn((await readFile(join(source,'public/js/main.js'),'utf8')).replace(/\r\n?/g,'\n'),'renderBalanceSettings');
  const literal=pattern=>{const match=pattern.exec(panel);if(!match)throw new Error('Missing source balance panel seam: '+pattern);return new Function('return ('+match[1]+');')();};
  const textFor=id=>literal(new RegExp(id+"\\.textContent = ('[^']*');"));
  const hintFor=id=>literal(new RegExp("attachTip\\("+id+", ('[^']*')\\)"));
  const tracks=literal(/const UPGRADE_TRACKS = (\[[\s\S]*?\n  \]);/);
  const stats=literal(/const STAT_PAIRS = (\[[\s\S]*?\n  \]);/);
  const rules={knobs:original.BALANCE_KNOBS,roundScale:scalar(/Math.round\(clamped \* ([\d.]+)\)/),
    combatTracks:[...text.matchAll(/item === '([^']+)'/g)].map(match=>match[1]),
    combatMinimum:scalar(/const minLvl = isCombat \? ([\d.]+)/),defenseMinimum:scalar(/const minLvl = isCombat \? [\d.]+ : ([\d.]+)/),
    combatMaximum:scalar(/const maxLvl = isCombat \? ([\d.]+)/),defenseMaximum:scalar(/const maxLvl = isCombat \? [\d.]+ : ([\d.]+)/),
    ui:{reset:textFor('reset'),groups:[
      {title:textFor('upgHead'),hint:hintFor('upgHead'),keys:tracks.flatMap(track=>['start','end'].map(end=>`upg_${track.id}_${end}`)).filter(key=>Object.hasOwn(original.BALANCE_KNOBS,key))},
      {title:textFor('statHead'),hint:hintFor('statHead'),keys:stats.filter(key=>Object.hasOwn(original.BALANCE_KNOBS,key))}]}};
  function create(saved,failWrites=false,raw=null,failReads=false) {
    const writes=[],notifications=[];
    const api=factory({getItem:()=>{if(failReads)throw new Error('fixture storage access');return raw??JSON.stringify(saved);},setItem:(key,value)=>{if(failWrites)throw new Error('fixture quota');writes.push({key,value:JSON.parse(value)});}});
    api.onBalanceChange(values=>notifications.push({...values}));
    return {api,writes,notifications};
  }
  const loads=[];
  for(const saved of [null,[],{},17,'bad',{stat_speed:null,upg_lw_start:'2.05',stat_cd:99,stat_sight:'Infinity',unknown:5},
    {stat_speed:[],stat_rate:[true],stat_dmg:'0x10',stat_respawn:false}]) {
    const {api}=create(saved);loads.push({saved,values:api.balancePrefs(),isDefault:api.balancePrefsDefault()});
  }
  const changes=[];
  const inputs=[null,false,true,[],[2.05],[true],{},'', ' \u00a02.05\ufeff','0x10','0b11','NaN','Infinity','-Infinity',-1,.14,.15,1,2.05,9.99,20];
  for(const key of [...Object.keys(rules.knobs),'unknown'])for(const input of inputs) {
    const {api,writes,notifications}=create({});
    const result=api.setBalancePref(key,input);
    const snapshot=api.balancePrefs();snapshot.stat_speed=999;
    const updated=api.balancePrefs(),isDefault=api.balancePrefsDefault();
    api.setBalancePref(key,input);api.resetBalancePrefs();api.resetBalancePrefs();
    changes.push({key,input,result,updated,isDefault,final:api.balancePrefs(),writes,notifications});
  }
  const curves=[];
  for(const item of ['lw','hw','sk','ult','hp','ar','sp','ch','def','atk','unknown']) {
    const saved={[`upg_${item}_start`]:.2,[`upg_${item}_end`]:3.4};
    const {api}=create(saved);
    for(const level of [-10,0,1,1.5,2,2.5,3,4,16,null,'2.5','Infinity','-Infinity'])
      curves.push({saved,item,level,value:api.upgradeCurveMul(item,level)});
  }
  const failing=create({},true);failing.api.setBalancePref('stat_speed',2);failing.api.resetBalancePrefs();
  const reads=[];
  for(const [raw,failReads] of [['{broken',false],['',false],['{}',true]]) {
    const {api}=create({},false,raw,failReads);
    reads.push({raw,failReads,values:api.balancePrefs(),isDefault:api.balancePrefsDefault()});
  }
  const queries=[];
  const query=create({stat_speed:2.1,stat_mpCost:.3,upg_lw_start:1.5});
  for(const key of [...Object.keys(rules.knobs),'unknown'])
    queries.push({key,pref:query.api.balancePref(key),multiplier:query.api.balanceMul(key.replace(/^stat_/,''))});
  const live=create({});let notified=null;const subscription=live.api.onBalanceChange(values=>{notified=values;});
  live.api.setBalancePref('stat_speed',2);const before=notified.stat_speed;
  subscription();live.api.setBalancePref('stat_speed',3);
  return {rules,fixtures:{balanceLoads:loads,balanceChanges:changes,balanceCurves:curves,
    balanceReads:reads,balanceQueries:{saved:query.api.balancePrefs(),queries},
    balanceLiveNotification:{before,after:notified.stat_speed},
    balanceWriteFailure:{notifications:failing.notifications,values:failing.api.balancePrefs()}}};
}
