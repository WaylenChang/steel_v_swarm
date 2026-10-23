// Only source shader text is translated; no renderer or compiler runs during capture.
export function captureMarineShader(shader, parts) {
  const clean=text=>text.replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*/g,'');
  const vertex=clean(shader.vertexShader),fragment=clean(shader.fragmentShader);
  const block=(text,start)=>{
    if(start<0||text[start]!=='{')throw new Error('Missing original marine shader block');
    let depth=0;
    for(let i=start;i<text.length;i++) {
      if(text[i]==='{')depth++;
      if(text[i]==='}') {
        depth--;
        if(depth===0)return text.slice(start+1,i);
      }
    }
    throw new Error('Unclosed original marine shader block');
  };
  const body=(text,marker)=>{
    const index=text.indexOf(marker);
    if(index<0||text.indexOf(marker,index+marker.length)>=0)throw new Error('Missing/ambiguous original marine shader seam: '+marker);
    const stack=[];
    for(let i=0;i<index;i++) {
      if(text[i]==='{')stack.push(i);
      if(text[i]==='}')stack.pop();
    }
    return block(text,stack.at(-1)??-1);
  };
  const fn=(text,name)=>{
    const match=new RegExp('\\b(?:float|vec[234])\\s+'+name+'\\s*\\([^)]*\\)\\s*\\{').exec(text);
    if(!match)throw new Error('Missing original marine shader function: '+name);
    const open=match.index+match[0].lastIndexOf('{');
    return text.slice(match.index,open+1)+block(text,open)+'}\n';
  };
  const normal=body(vertex,'vec2 seaN0 =');
  const reflection=body(vertex,'float rE =');
  let displacement=body(vertex,'vec2 seaXZ =');
  if(!displacement.includes('vSeaFade = seaFade;'))throw new Error('Missing original wave fade assignment');
  displacement=displacement.replace('vSeaFade = seaFade;','');
  const finish=body(fragment,'float celF = celFoam(').replaceAll('gl_FragColor','nativeColor');
  const lighting=body(fragment,'vec3 celV =').replaceAll('celKeyColor()','nativeKeyColor');
  const wash=body(fragment,'float celN = celNoise( vCelWP.xz * 0.011 );')
    .replaceAll('celWeatherF()','celWeatherF(vCelWP)');
  const weather=fn(fragment,'celWeatherF').replace('celWeatherF()','celWeatherF(vec3 vCelWP)');
  const cut=parts.school==='b' ? `
uniform float uCelCutLo;
uniform float uCelCutHi;
uniform float uCelShadowV;
uniform float uCelCutWidth;
${fn(fragment,'celLum')}
` : '';
  for(const key of ['wind','ripple','sea'])if(typeof parts?.[key]!=='string'||!parts[key].trim())
    throw new Error('Missing expanded original marine shader program: '+key);
  const code=`// Generated from the original marine shader; do not edit derived resources.
uniform sampler2D uSeaField : filter_linear, repeat_disable;
uniform vec4 uSeaRect;
uniform float uWaterY;
uniform float uFoamA;
uniform vec3 uFoamC;
uniform vec3 uNativeKeyColor;
uniform vec3 uCelRampTint;
uniform float uCelRampFb;
uniform float uCelRampLo;
uniform float uCelRim;
uniform float uCelRimScale;
uniform float uRenderStyle;
uniform float uCelWash;
uniform float uCelCool;
uniform sampler2D gradientMap : filter_nearest, repeat_disable;
uniform sampler2D uCelWField : filter_linear, repeat_disable;
uniform vec4 uCelWRect;
uniform float uCelWSpread;
float saturate(float value) { return clamp(value, 0.0, 1.0); }
#define RECIPROCAL_PI (1.0 / PI)
${cut}
${fn(fragment,'celRampDepth')}
${fn(fragment,'getGradientIrradiance')}
${fn(clean(parts.common),'inverseTransformDirection')}
${clean(parts.wind)}
${clean(parts.ripple)}
${clean(parts.sea)}
${fn(fragment,'celHash')}
${fn(fragment,'celNoise')}
${fn(fragment,'celFoam')}
${weather}
void celMarineWash(inout vec4 diffuseColor, vec3 vCelWP) {
  #ifdef CEL_WASH
  ${wash}
  #endif
}
struct NativeMarineLight {
  vec3 directDiffuse;
  vec3 indirectDiffuse;
};
vec3 celMarineLightFinish(vec3 outgoingLight, vec4 diffuseColor, vec3 diffuse, vec3 directDiffuse, vec3 indirectDiffuse,
  vec3 totalEmissiveRadiance, vec3 vCelWP, vec3 vViewPosition, vec3 normal, mat4 viewMatrix, vec3 uCelLightDir, vec3 nativeKeyColor) {
  NativeMarineLight reflectedLight;
  reflectedLight.directDiffuse = directDiffuse;
  reflectedLight.indirectDiffuse = indirectDiffuse;
  ${lighting}
  return outgoingLight;
}
vec3 celMarineNormal(vec3 position, mat4 modelMatrix, float seaFade) {
  vec3 objectNormal;
  ${normal}
  return objectNormal;
}
void celMarineReflection(inout vec3 transformed, vec3 aReflO, vec3 cameraPosition, float seaFade) {
  ${reflection}
}
void celMarineDisplace(inout vec3 transformed, mat4 modelMatrix, float seaFade) {
  ${displacement}
}
void celMarineFinish(inout vec4 nativeColor, vec3 vCelWP, float vSeaFade, vec3 vViewPosition, vec3 normal, vec3 uCelLightDir) {
  ${finish}
}
`;
  const result=code.replaceAll('texture2D(','texture(').replaceAll('texture2D (','texture (')
    .replace(/texture2D\s+\(/g,'texture(');
  if(/\b(?:attribute|varying|gl_FragColor|texture2D)\b|#include/.test(result))
    throw new Error('Untranslated Three shader dependency in native marine program');
  return result;
}
