// Execute the original material hook; do not infer expansion from model size.
export function captureOutlineUniforms(material) {
  if (!material || material.customProgramCacheKey?.() !== 'celOutline')
    throw new Error('Missing original inverted-hull outline material');
  const shader = {uniforms:{},vertexShader:'#include <begin_vertex>',fragmentShader:'#include <color_fragment>'};
  material.onBeforeCompile(shader);
  const result = {width:shader.uniforms.uOW?.value,minimum:shader.uniforms.uOMin?.value,maximum:shader.uniforms.uOMax?.value};
  if (!Object.values(result).every(Number.isFinite)) throw new Error('Invalid original outline width uniforms');
  return result;
}
