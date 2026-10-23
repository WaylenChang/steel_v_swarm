import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {marineVisualReferences} from './marine_visual_references.mjs';

export async function visualReferences(source) {
  const text=await readFile(join(source,'public/js/visualPrefs.js'),'utf8');
  const create=raw=>{
    let saved=raw,notifications=0;
    const storage={getItem:()=>saved,setItem:(_key,value)=>{saved=value;}};
    const api=new Function('localStorage',text.replace(/^export\s+/gm,'')+`
return {knobs:VISUAL_KNOBS,presets:VISUAL_PRESETS,defaultPreset:DEFAULT_VISUAL_PRESET,
  preset:visualPreset,values:visualPrefs,value:visualPref,set:setVisualPref,select:setVisualPreset,
  reset:resetVisualPrefs,isDefault:visualPrefsDefault,subscribe:onVisualChange};`)(storage);
    api.subscribe(()=>notifications++);
    return {api,state:()=>{
      let parsed=null;
      try { if(saved!=null)parsed=JSON.parse(saved); } catch {}
      return {preset:api.preset().id,values:api.values(),isDefault:api.isDefault(),notifications,saved:parsed};
    }};
  };
  const baseline=create(null),rules={knobs:baseline.api.knobs,presets:baseline.api.presets,defaultPreset:baseline.api.defaultPreset};
  const programs=[];
  for(const raw of [null,'{',JSON.stringify({preset:'unknown',worldTextLang:'xx',foam:1}),
    JSON.stringify({preset:rules.presets.at(-1).id,worldTextLang:'en',renderStyle:'cel',reflect:1}),
    JSON.stringify({preset:rules.defaultPreset,worldTextLang:null})]) {
    const run=create(raw),initial=run.state(),frames=[];
    const calls=[['set','reflect',.75],['set','reflect',.75],['set','foam',100],['set','foam',-10],
      ['set','weather','0.65'],['set','weather',null],['set','weather',{}],['set','weather',[.3]],
      ['set','weather','0x1'],['set','weather','0b10'],['set','weather','invalid'],
      ['set','weather','\u00a0\ufeff0.45\u2003'],['set','weather',[]],['set','weather',[[.3333333333333333]]],
      ['set','weather',[true]],['set','weather',[null]],['set','weather',[1,2]],['set','weather','+0x1'],['set','weather','0o1'],
      ['set','worldTextLang','en'],['select',rules.presets[1].id],['set','shadowEnv',1.4],
      ['select',rules.presets[1].id],['select','unknown'],['set','renderStyle','unknown'],
      ['set','not_a_visual_setting',1],['reset'],['reset']];
    for(const call of calls) {
      const [operation,...args]=call;
      const result=run.api[operation](...args);
      const state=run.state();
      const reloaded=create(state.saved==null?null:JSON.stringify(state.saved)).state();
      frames.push({call,result:result??null,...state,reloaded});
    }
    programs.push({raw,initial,frames});
  }
  return {rules,fixtures:{visualPreferencePrograms:programs,marineVisualPrograms:await marineVisualReferences(source,create)},
    inputs:['public/js/visualPrefs.js','public/js/toon.js','public/js/biomes.js','out/forest_review/three.module.js']};
}
