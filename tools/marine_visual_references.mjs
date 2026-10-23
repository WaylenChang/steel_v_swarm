import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function marineVisualReferences(source, createPreferences) {
  const {grabConst,grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const toon=(await readFile(join(source,'public/js/toon.js'),'utf8')).replace(/\r\n?/g,'\n');
  const biomes=(await readFile(join(source,'public/js/biomes.js'),'utf8')).replace(/\r\n?/g,'\n');
  const compile=(code,scope,name)=>new Function(...Object.keys(scope),code+'\nreturn '+name+';')(...Object.values(scope));
  const literal=(name,scope={})=>{
    const match=new RegExp('(?:export )?const '+name+' = ([^\n]*);').exec(toon);
    if(!match)throw new Error('Missing original visual literal: '+name);
    return compile(match[0].replace(/^export /,''),scope,name);
  };
  const RAMPS=compile(grabConst(toon,'RAMPS'),{},'RAMPS');
  const rampFloor=compile(grabFn(toon,'rampFloor'),{RAMPS},'rampFloor');
  const CEL_CUT=compile(grabConst(toon,'CEL_CUT'),{rampFloor,SHADOW_V_F:literal('SHADOW_V_F')},'CEL_CUT');
  const SHADOW_HUE=literal('SHADOW_HUE'),LUMA_709=literal('LUMA_709');
  const start=toon.indexOf('const SHADOW_HUE_N ='),end=toon.indexOf('})();',start);
  if(start<0||end<0)throw new Error('Missing original luminance-normalized shadow hue');
  const SHADOW_HUE_N=compile(toon.slice(start,end+5),{SHADOW_HUE,LUMA_709},'SHADOW_HUE_N');
  const TINT_MAX_A=literal('TINT_MAX_A'),WEATHER_SPREAD=literal('WEATHER_SPREAD');
  const shadowTintRGB=compile(grabFn(toon,'shadowTintRGB'),{TINT_MAX_A,SHADOW_HUE_N},'shadowTintRGB');
  const RENDER_STYLES=compile(grabConst(toon,'RENDER_STYLES'),{},'RENDER_STYLES');
  const OUTLINE_STYLE_SCALE=literal('OUTLINE_STYLE_SCALE');
  const reflectionDeclaration=/const REFL_C = [^\n]*;/.exec(biomes);
  if(!reflectionDeclaration)throw new Error('Missing original reflection alpha declaration');
  const REFL_A=compile(reflectionDeclaration[0],{},'REFL_A');
  const reflectionStart=biomes.indexOf("const a = visualPref('reflect');");
  const reflectionEnd=biomes.indexOf('\n  });',reflectionStart);
  if(reflectionStart<0||reflectionEnd<0)throw new Error('Missing original live reflection preference callback');
  const programs=[];
  for(const school of ['a','b']) {
    const run=createPreferences(null),api=run.api;
    const scope={visualPreset:api.preset,visualPref:api.value,_school:school,CEL_CUT,rampFloor,shadowTintRGB,WEATHER_SPREAD,OUTLINE_STYLE_SCALE,
      _rampTint:{env:{value:new THREE.Color()},mech:{value:new THREE.Color()}},outlineInkUniform:{value:new THREE.Color()}};
    for(const key of ['_celCutWidth','_celShadowValue','_celRimScale','_wSpread','_foamA','_inkBreakA','_landInkA','_renderStyle','_outlineStyleScale'])scope[key]={value:0};
    scope.tintA=literal('tintA',{visualPref:api.value,_school:school,CEL_CUT});
    scope.renderStyleIndex=compile(grabFn(toon,'renderStyleIndex'),{visualPref:api.value,RENDER_STYLES},'renderStyleIndex');
    const sync=compile(grabFn(toon,'syncVisualPrefs'),scope,'syncVisualPrefs');
    const mesh={visible:false},mat={opacity:REFL_A};
    const reflect=new Function('visualPref','mesh','mat','REFL_A','return function(){'+biomes.slice(reflectionStart,reflectionEnd)+'};')(api.value,mesh,mat,REFL_A);
    const calls=[...api.presets.map(preset=>['select',preset.id]),['set','shadowEnv',0],['set','shadowEnv',3],['set','shadowEnv',-1],
      ['set','foam',.8],['set','weather',1.5],['set','reflect',.75],['set','reflect',1.5],['set','reflect',0],['set','reflect',0],['set','reflect',.25],['reset']];
    const frames=[];
    for(const call of [['initial'],...calls]) {
      if(call[0]!=='initial')api[call[0]](...call.slice(1));
      sync();reflect();
      frames.push({call,visible:mesh.visible,opacity:mat.opacity,outline:{scale:scope._outlineStyleScale.value,ink:scope.outlineInkUniform.value.toArray()},uniforms:{uCelCutWidth:scope._celCutWidth.value,
        uCelShadowV:scope._celShadowValue.value,uCelRimScale:scope._celRimScale.value,uCelRampTint:scope._rampTint.env.value.toArray(),
        uCelWSpread:scope._wSpread.value,uFoamA:scope._foamA.value,uRenderStyle:scope._renderStyle.value}});
    }
    programs.push({appearance:{school,weatherSpread:WEATHER_SPREAD,renderStyles:RENDER_STYLES,shadowFloor:rampFloor(3),shadowValue:CEL_CUT.SHADOW_V,
      hueMinimum:CEL_CUT.HUE_MIN_A,shadowHueNormalized:SHADOW_HUE_N,tintMaximum:TINT_MAX_A},reflectionAlpha:REFL_A,frames});
  }
  return programs;
}
