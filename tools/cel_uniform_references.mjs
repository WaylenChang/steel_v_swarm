import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createCelCapture} from './cel_capture.mjs';
import {describeSourceTexture} from './texture_capture.mjs';

export async function celUniformReferences(source) {
  const path=join(source,'out/forest_review/three.module.js');
  const THREE=await import(pathToFileURL(path).href),text=(await readFile(path,'utf8')).replace(/\r\n?/g,'\n');
  const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const setters=['setValueV1f','setValueV2f','setValueV3f','setValueV4f','setValueM3','setValueM4',
    'setValueV1i','setValueV1ui','setValueV2i','setValueV3i','setValueV4i',
    'setValueV1fArray','setValueV2fArray','setValueV3fArray','setValueV4fArray','setValueV1iArray','setValueM3Array','setValueM4Array'];
  const original=new Function('arrayCacheF32','mat3array','mat4array',
    ['flatten','arraysEqual','copyArray',...setters].map(name=>grabFn(text,name)).join('\n')+'\nreturn {'+setters.join(',')+'};')
    ([],new Float32Array(9),new Float32Array(16));
  const cel=createCelCapture(THREE,()=>{throw new Error('Numeric uniform references cannot capture an image');},texture=>describeSourceTexture(texture,THREE,true));
  const jobs=[];
  for(const value of [0,-0,.03125,1.75,16777217,1e-36,Infinity,-Infinity,NaN])jobs.push({type:'float',setter:'setValueV1f',value});
  for(const type of ['int','bool','uint'])for(const value of [-.75,.5,4294967297,-4294967297,2147483648,NaN])
    jobs.push({type,setter:type==='uint'?'setValueV1ui':'setValueV1i',value});
  for(const value of [true,false])jobs.push({type:'bool',setter:'setValueV1i',value});
  const matrix3=new THREE.Matrix3().set(1,.25,-0,4,5,6,7,8,9);
  const matrix4=new THREE.Matrix4().set(1,2,3,4,5,6,7,8,9,10,11,12,13,14,-0,16);
  jobs.push(
    {type:'vec2',setter:'setValueV2f',value:new THREE.Vector2(.2,-0)},
    {type:'vec3',setter:'setValueV3f',value:[.1,.3,.7]},
    {type:'vec3',setter:'setValueV3f',value:new THREE.Color().setRGB(.15,.3,.5),hint:'source_color'},
    {type:'vec4',setter:'setValueV4f',value:new THREE.Quaternion(.2,-.3,.4,.5)},
    {type:'vec4',setter:'setValueV4f',value:new Float32Array([.2,-0,.4,.5]),hint:'source_color'},
    {type:'ivec2',setter:'setValueV2i',value:new THREE.Vector2(1.9,-1.9)},
    {type:'ivec3',setter:'setValueV3i',value:new THREE.Vector3(4294967295,2.8,-2.8)},
    {type:'ivec4',setter:'setValueV4i',value:new THREE.Vector4(2147483648,4294967297,-4294967297,0)},
    {type:'mat3',setter:'setValueM3',value:matrix3},
    {type:'mat4',setter:'setValueM4',value:matrix4},
    {type:'float',size:4,setter:'setValueV1fArray',value:new Float32Array([.1,-0,.3,1e-36])},
    {type:'int',size:4,setter:'setValueV1iArray',value:new Int32Array([3,-4,2147483647,-2147483648])},
    {type:'vec2',size:2,setter:'setValueV2fArray',value:[new THREE.Vector2(.1,.2),new THREE.Vector2(-0,.4)]},
    {type:'vec3',size:2,setter:'setValueV3fArray',value:[new THREE.Color().setRGB(.2,.4,.6),new THREE.Color().setRGB(.8,.1,.3)],hint:'source_color'},
    {type:'vec3',size:2,setter:'setValueV3fArray',value:[new THREE.Color().setRGB(.2,.4,.6),new THREE.Vector3(.8,.1,.3)]},
    {type:'vec4',size:2,setter:'setValueV4fArray',value:[new THREE.Vector4(1,2,3,4),new THREE.Vector4(5,6,7,8)]},
    {type:'vec4',size:2,setter:'setValueV4fArray',value:[new THREE.Vector4(1,2,3,4),new THREE.Quaternion(.2,-.3,.4,.5)]},
    {type:'mat3',size:2,setter:'setValueM3Array',value:[matrix3,matrix3.clone().transpose()]},
    {type:'mat4',size:2,setter:'setValueM4Array',value:[matrix4,matrix4.clone().transpose()]});
  const cases=[],declarations=[],entries={};
  for(const [index,job]of jobs.entries()) {
    const name='u_source_'+index,writes=[];
    const record=(method,address,input)=>{
      if(address!==name)throw new Error('Original uniform upload changed its location');
      const kind=/ui[v]?$/.test(method)?'u32':/i[v]?$/.test(method)?'i32':'f32';
      const typed=kind==='u32'?new Uint32Array(input):kind==='i32'?new Int32Array(input):new Float32Array(input);
      writes.push({kind,bytes:Array.from(new Uint8Array(typed.buffer)),finite:typed.every(Number.isFinite),
        values:Array.from(typed,value=>Number.isFinite(value)?value:Number.isNaN(value)?'NaN':value>0?'Infinity':'-Infinity')});
    };
    const gl=new Proxy({}, {get(_target,method){
      if(!/^uniform(?:[1-4](?:f|i|ui)v?|Matrix[34]fv)$/.test(method))throw new Error('Unexpected original uniform upload: '+method);
      return (address,...args)=>{
        if(method.startsWith('uniformMatrix')) {
          if(args[0]!==false)throw new Error('Original matrix upload unexpectedly transposes columns');
          record(method,address,args[1]);
        } else record(method,address,method.endsWith('v')?args[0]:args);
      };
    }});
    original[job.setter].call({addr:name,cache:[],size:job.size??1},gl,job.value);
    if(writes.length!==1)throw new Error('Original fresh uniform must upload exactly once: '+job.setter);
    entries[name]=cel.uniform(job.value);
    declarations.push(`uniform ${job.type} ${name}${job.size?'['+job.size+']':''}${job.hint?' : '+job.hint:''};`);
    cases.push({name,type:job.type,size:job.size??1,...writes[0]});
  }
  return {celUniformCases:cases,celUniformEntries:entries,
    celUniformShader:'shader_type spatial;\n'+declarations.join('\n')+'\nvoid fragment() { ALBEDO=vec3(1.0); }'};
}
