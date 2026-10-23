import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function outlineReferences(source) {
  const {grabFn,grabConst}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const text=(await readFile(join(source,'public/js/toon.js'),'utf8')).replace(/\r\n?/g,'\n');
  const geometryText=await readFile(join(source,'public/js/geo3d.js'),'utf8');
  const unitWidthDeclaration=/export const outlineW = ([^;]+);/.exec(geometryText)?.[1];
  const unitWidthParts=/Math\.min\(([\d.]+), Math\.max\(([\d.]+), target \* ([\d.]+)\)\)/.exec(unitWidthDeclaration??'');
  if(!unitWidthParts) throw new Error('Missing original unit outline width clamps');
  const unitWidth=new Function('return '+unitWidthDeclaration)();
  const unitWidthRules={maximum:Number(unitWidthParts[1]),minimum:Number(unitWidthParts[2]),factor:Number(unitWidthParts[3])};
  const unitWidths=[-1,0,1,unitWidthRules.minimum/unitWidthRules.factor,4,20,
    unitWidthRules.maximum/unitWidthRules.factor,100].map(target=>({target,result:unitWidth(target)}));
  const literal=name=>{
    const declaration=new RegExp('const '+name+' = ([^\n]+);').exec(text);
    if(!declaration) throw new Error('Missing original outline constant: '+name);
    return new Function('return '+declaration[1])();
  };
  const outlineInkUniform={value:new THREE.Color(0)},_outlineStyleScale={value:1};
  const scope={THREE,OUTLINE_COLOR:outlineInkUniform.value,outlineInkUniform,_outlineStyleScale,
    OUTLINE_MIN_NDC:literal('OUTLINE_MIN_NDC'),OUTLINE_MAX_NDC:literal('OUTLINE_MAX_NDC'),_ws:new THREE.Vector3()};
  const compile=(name,bindings)=>new Function(...Object.keys(bindings),grabFn(text,name).replace(/^export /,'')+'\nreturn '+name+';')(...Object.values(bindings));
  scope.outlineMaterial=compile('outlineMaterial',scope);
  const outlinify=compile('outlinify',scope);
  const defaultWidth=Number(/outlinify\(root, width = ([\d.]+)\)/.exec(text)?.[1]);
  const capture=material=>{
    const shader={uniforms:{},vertexShader:'#include <begin_vertex>',fragmentShader:'#include <color_fragment>'};
    material.onBeforeCompile(shader);
    return shader;
  };
  const sampleMaterial=scope.outlineMaterial(defaultWidth,1),sample=capture(sampleMaterial);
  const depthMinimum=Number(/float oDist = max\(\s*([\d.]+)/.exec(sample.vertexShader)?.[1]);
  const projectionMinimum=Number(/max\(\s*([\d.]+),\s*projectionMatrix/.exec(sample.vertexShader)?.[1]);
  const minExpression=/float oMinW = ([^;]+);/.exec(sample.vertexShader)?.[1];
  const maxExpression=/float oMaxW = ([^;]+);/.exec(sample.vertexShader)?.[1];
  const offsetExpression=/vec3 transformed = position \+ normal \* \(([^;]+)\);/.exec(sample.vertexShader)?.[1];
  if(![defaultWidth,depthMinimum,projectionMinimum].every(Number.isFinite)||!minExpression||!maxExpression||!offsetExpression)
    throw new Error('Missing original outline camera-depth/projection clamps');
  const expression=body=>body.replaceAll('projectionMatrix[1][1]','projectionY').replace(/\b(max|min)\(/g,'Math.$1(');
  const offset=new Function('uOW','uOMin','uOMax','oDist','projectionY','uOScale',
    `const oMinW=${expression(minExpression)};const oMaxW=${expression(maxExpression)};return ${expression(offsetExpression)};`);
  const uniforms=[],widths=[];
  const scales=[[1,1,1],[.01,.01,.01],[100,100,100],[-2,3,4],[0,0,0],[.2,3,8]];
  const geometry=new THREE.BoxGeometry(),base=new THREE.MeshBasicMaterial();
  for(const scale of scales) for(const width of [0,defaultWidth,defaultWidth*100]) {
    const root=new THREE.Group(),mesh=new THREE.Mesh(geometry,base);
    root.scale.set(...scale);root.rotation.y=.37;mesh.rotation.z=.29;root.add(mesh);
    outlinify(root,width);
    const shell=mesh.children.find(child=>child.userData.isOutline);
    if(!shell) throw new Error('Original opaque mesh lost its outline shell');
    const shader=capture(shell.material),u=shader.uniforms,matrix=mesh.matrixWorld.elements;
    const values={width:u.uOW.value,minimum:u.uOMin.value,maximum:u.uOMax.value};
    uniforms.push({basis:[...matrix.slice(0,3),...matrix.slice(4,7),...matrix.slice(8,11)],width,result:values});
    for(const depth of [-1,0,depthMinimum*.999,depthMinimum,1,100,10000])
      for(const projection of [0,projectionMinimum*.5,projectionMinimum,.7,4])
        for(const style of [0,...new Set(literal('OUTLINE_STYLE_SCALE'))])
          widths.push({uniforms:values,depth,projection,style,result:offset(values.width,values.minimum,values.maximum,Math.max(depthMinimum,depth),projection,style)});
    shell.material.dispose();
  }
  sampleMaterial.dispose();geometry.dispose();base.dispose();
  const renderStyles=new Function(grabConst(text,'RENDER_STYLES').replace(/^export /,'')+'\nreturn RENDER_STYLES;')();
  return {rules:{minimumNdc:scope.OUTLINE_MIN_NDC,maximumNdc:scope.OUTLINE_MAX_NDC,defaultWidth,depthMinimum,projectionMinimum,
    unitWidth:unitWidthRules,styleScales:literal('OUTLINE_STYLE_SCALE'),renderStyles,vertexSource:sample.vertexShader,fragmentSource:sample.fragmentShader},
    fixtures:{outlineUniforms:uniforms,outlineWidths:widths,outlineUnitWidths:unitWidths}};
}
