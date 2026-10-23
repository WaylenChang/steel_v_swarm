// Offline preservation only. Raw source GLSL is never evaluated by the native game.
export function createCelCapture(THREE, textureCapture, describeSampler) {
  const programs=[],samplers=[],programIds=new Map(),samplerIds=new WeakMap();
  const finite=(values,label)=>{
    if(!values.every(Number.isFinite))throw new Error('Non-finite original cel '+label);
    return values;
  };
  const numberList=values=>{
    const negativeZeros=[];
    for(let index=0;index<values.length;index++)if(Object.is(values[index],-0))negativeZeros.push(index);
    return {value:values,...(negativeZeros.length?{negativeZeros}:{})};
  };
  const sampler=texture=>{
    if(samplerIds.has(texture))return samplerIds.get(texture);
    let description;
    const image=texture.image;
    if(image?.data) {
      if(texture.isCompressedTexture||texture.isCubeTexture||texture.isDepthTexture||texture.mipmaps.length)
        throw new Error('Unsupported original cel data sampler');
      const formats=new Map([[THREE.RedFormat,1],[THREE.RGFormat,2],[THREE.RGBFormat,3],[THREE.RGBAFormat,4]]);
      const channels=formats.get(texture.format);
      if(!channels||!Number.isInteger(image.width)||!Number.isInteger(image.height)||image.width<=0||image.height<=0
        ||!ArrayBuffer.isView(image.data)||image.data.length!==image.width*image.height*channels)
        throw new Error('Invalid original cel data sampler extent/format');
      if(texture.matrixAutoUpdate)texture.updateMatrix();
      const sampleTypes=new Map([[THREE.UnsignedByteType,'unorm8'],[THREE.HalfFloatType,'float16'],[THREE.FloatType,'float32']]);
      if(!image.data.every(Number.isFinite))throw new Error('Non-finite original cel sampler data');
      const bytes=new Uint8Array(image.data.buffer,image.data.byteOffset,image.data.byteLength),parts=[];
      for(let offset=0;offset<bytes.length;offset+=8192)parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
      description={kind:'data',width:image.width,height:image.height,channels,format:texture.format,type:texture.type,
        sampleType:sampleTypes.get(texture.type)??'unsupported',sampling:describeSampler(texture),
        storage:image.data.constructor.name,elementSize:image.data.BYTES_PER_ELEMENT,bytes:btoa(parts.join('')),
        matrix:finite(texture.matrix.toArray(),'sampler transform'),mapping:texture.mapping,channel:texture.channel,
        wrapS:texture.wrapS,wrapT:texture.wrapT,min:texture.minFilter,mag:texture.magFilter,
        mipmaps:!!texture.generateMipmaps,flipY:!!texture.flipY,premultiplyAlpha:!!texture.premultiplyAlpha,
        unpackAlignment:texture.unpackAlignment,srgb:texture.colorSpace===THREE.SRGBColorSpace,
        colorSpace:texture.colorSpace,anisotropy:texture.anisotropy};
    } else description={kind:'image',texture:textureCapture(texture)};
    const id=samplers.length;
    samplerIds.set(texture,id);samplers.push(description);
    return id;
  };
  const encode=(value,ancestors=new Set())=>{
    if(value===undefined)return {type:'undefined'};
    if(value===null)return {type:'null'};
    if(typeof value==='number') {
      if(!Number.isFinite(value))return {type:'nonfinite',value:Number.isNaN(value)?'NaN':value>0?'Infinity':'-Infinity'};
      return {type:'number',value,...(Object.is(value,-0)?{negativeZero:true}:{})};
    }
    if(typeof value==='boolean'||typeof value==='string')return {type:typeof value,value};
    if(value.isTexture)return {type:'sampler',value:sampler(value)};
    const kind=value.isColor?'color':value.isVector2?'vec2':value.isVector3?'vec3':value.isVector4?'vec4':value.isQuaternion?'quaternion'
      :value.isMatrix3?'mat3':value.isMatrix4?'mat4':null;
    if(kind)return {type:kind,...numberList(finite(value.toArray(),'uniform '+kind))};
    if(ancestors.has(value))throw new Error('Cyclic original cel uniform/options');
    ancestors.add(value);
    let result;
    if(Array.isArray(value))result={type:'array',value:value.map(item=>encode(item,ancestors))};
    else if(ArrayBuffer.isView(value))result={type:'buffer',storage:value.constructor.name,...numberList(finite(Array.from(value),'uniform buffer'))};
    else if(Object.getPrototypeOf(value)===Object.prototype)
      result={type:'object',value:Object.fromEntries(Object.entries(value).map(([key,item])=>[key,encode(item,ancestors)]))};
    else throw new Error('Unsupported original cel uniform/options object: '+value.constructor?.name);
    ancestors.delete(value);
    return result;
  };
  const program=shader=>{
    const chunks={};
    const collect=code=>{
      for(const match of code.replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*/g,'').matchAll(/#include\s*<([^>]+)>/g)) {
        const name=match[1];
        if(Object.hasOwn(chunks,name))continue;
        const chunk=THREE.ShaderChunk[name];
        if(typeof chunk!=='string')throw new Error('Missing original cel shader chunk: '+name);
        chunks[name]=chunk;collect(chunk);
      }
    };
    collect(shader.vertexShader);collect(shader.fragmentShader);
    const description={vertex:shader.vertexShader,fragment:shader.fragmentShader,chunks};
    const key=JSON.stringify(description);
    if(!programIds.has(key)){programIds.set(key,programs.length);programs.push(description);}
    return programIds.get(key);
  };
  const capture=material=>{
    const library=material.isMeshToonMaterial?'toon':material.isMeshBasicMaterial?'basic':material.isMeshLambertMaterial?'lambert'
      :material.isMeshPhongMaterial?'phong':material.isMeshPhysicalMaterial?'physical':material.isMeshStandardMaterial?'standard':null;
    if(!library||!THREE.ShaderLib[library])throw new Error('Unsupported original cel material shader library: '+material.type);
    const shader={uniforms:{},vertexShader:THREE.ShaderLib[library].vertexShader,fragmentShader:THREE.ShaderLib[library].fragmentShader};
    material.onBeforeCompile(shader);
    const properties=Object.fromEntries(Object.entries(material).filter(([key,value])=>!['id','version'].includes(key)
      &&(typeof value==='number'||typeof value==='boolean'||value?.isColor||value?.isVector2||value?.isVector3
        ||value?.isVector4||value?.isMatrix3||value?.isMatrix4||value?.isTexture)).map(([key,value])=>[key,encode(value)]));
    return {library,family:material.userData?.celOpts?'patched':material.isMeshToonMaterial?'plain':'native',
      program:program(shader),defines:{...material.defines},options:encode(material.userData?.celOpts),properties,
      uniforms:Object.fromEntries(Object.entries(shader.uniforms).map(([key,uniform])=>[key,encode(uniform.value)])),
      gradient:material.gradientMap?sampler(material.gradientMap):null};
  };
  const attributes=geometry=>Object.fromEntries(Object.entries(geometry.attributes).filter(([name])=>
    !['position','normal','color','uv','uv1','uv2','uv3'].includes(name)).map(([name,attribute])=>{
      if(!Number.isInteger(attribute.itemSize)||attribute.itemSize<1||attribute.itemSize>4)
        throw new Error('Unsupported original cel vertex attribute size: '+name);
      const getters=['getX','getY','getZ','getW'].slice(0,attribute.itemSize);
      const values=finite(Array.from({length:attribute.count},(_,index)=>getters.map(key=>attribute[key](index))).flat(),'vertex '+name);
      return [name,{size:attribute.itemSize,count:attribute.count,normalized:!!attribute.normalized,
        instanced:!!(attribute.isInstancedBufferAttribute||attribute.data?.isInstancedInterleavedBuffer),
        meshPerAttribute:attribute.meshPerAttribute??attribute.data?.meshPerAttribute??1,values}];
    }));
  return {capture,attributes,uniform:encode,programs,samplers};
}
