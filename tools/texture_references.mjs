import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {readFile} from 'node:fs/promises';
import {captureTextureImage, describeSourceTexture} from './texture_capture.mjs';
import {createCelCapture} from './cel_capture.mjs';

export async function textureReferences(source) {
  const THREE = await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const pixels = new Uint8Array([255,0,0,255, 0,255,0,128, 0,0,255,0, 80,120,160,255,
    20,60,100,255, 240,160,80,64, 140,200,40,255, 30,90,210,192]);
  const points = [];
  for (const u of [-2.125,-1.125,-.125,0,.125,.375,.875,1,1.125,2.125])
    for (const v of [-1.125,-.125,0,.125,.375,.875,1,1.125]) points.push([Math.fround(u),Math.fround(v)]);
  const textureCases = [];
  let textureImageCapture;
  const wraps = [THREE.ClampToEdgeWrapping,THREE.RepeatWrapping,THREE.MirroredRepeatWrapping];
  for (const s of wraps) for (const t of wraps) for (const style of [0,1,2,3])
    for (const flipY of [false,true]) for (const srgb of [false,true]) {
      const texture = new THREE.DataTexture(pixels,4,2,THREE.RGBAFormat);
      texture.wrapS = s; texture.wrapT = t; texture.flipY = flipY;
      texture.magFilter = THREE.NearestFilter; texture.minFilter = THREE.NearestFilter;
      texture.generateMipmaps = false; texture.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
      if (style === 1) {texture.repeat.set(2.2,1.4);texture.offset.set(.2,-.3);texture.center.set(.3,.7);texture.rotation=Math.PI/6;}
      if (style === 2) {texture.repeat.set(-1.5,2.4);texture.offset.set(1.2,-.5);texture.channel=1;}
      if (style === 3) {texture.matrixAutoUpdate=false;texture.matrix.set(.8,.2,.1,-.4,1.1,.3,0,0,1);}
      const spec = {...describeSourceTexture(texture,THREE),image:0};
      textureImageCapture ??= captureTextureImage(texture,true);
      const probes = points.map(point=>{
        const uv = texture.transformUv(new THREE.Vector2(...point));
        // Repeat sampling maps the exact upper endpoint back to its first texel.
        const u = s === THREE.RepeatWrapping ? uv.x-Math.floor(uv.x) : uv.x;
        const v = t === THREE.RepeatWrapping ? uv.y-Math.floor(uv.y) : uv.y;
        const x = Math.max(0,Math.min(3,Math.floor(u*4))), y = Math.max(0,Math.min(1,Math.floor(v*2)));
        return {point,rgba:Array.from(pixels.slice((y*4+x)*4,(y*4+x+1)*4)).map(value=>value/255)};
      });
      textureCases.push({spec,rawUV:points.flat(),probes});
      texture.dispose();
    }
  const {grabConst,grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const toon=(await readFile(join(source,'public/js/toon.js'),'utf8')).replace(/\r\n?/g,'\n');
  const RAMPS=new Function(grabConst(toon,'RAMPS')+'\nreturn RAMPS;')();
  const gradient=new Function('THREE','RAMPS','_grads',grabFn(toon,'toonGradient').replace(/^export /,'')+'\nreturn toonGradient;')(THREE,RAMPS,new Map());
  const cel=createCelCapture(THREE,()=>{throw new Error('Data sampler references cannot introduce an uncaptured image');},
    texture=>describeSourceTexture(texture,THREE,true));
  const celSamplerCases=[];
  const captureData=(texture,label,channels,decode)=>{
    const material=new THREE.MeshBasicMaterial({map:texture});
    const captured=cel.capture(material),index=captured.properties.map.value;
    const data=texture.image.data;
    const rgba=Array.from({length:texture.image.width*texture.image.height},(_,pixel)=>{
      const result=[0,0,0,1];
      for(let channel=0;channel<channels;channel++)result[channel]=decode(data[pixel*channels+channel]);
      return result;
    });
    celSamplerCases.push({label,index,rgba,bytes:Array.from(new Uint8Array(data.buffer,data.byteOffset,data.byteLength)),
      width:texture.image.width,height:texture.image.height,channels,sampling:describeSourceTexture(texture,THREE,true)});
    material.dispose();
  };
  for(const key of [...Object.keys(RAMPS),'unknown']) {
    const texture=gradient(key);
    if(gradient(key)!==texture)throw new Error('Original cel gradient cache lost its identity');
    captureData(texture,'source-ramp-'+key,1,value=>value/255);
  }
  const formats=[[THREE.RedFormat,1],[THREE.RGFormat,2],[THREE.RGBFormat,3],[THREE.RGBAFormat,4]]
    .filter(([format])=>Number.isFinite(format));
  for(const [format,channels]of formats)for(const kind of ['unorm8','float16','float32']) {
    const seed=kind==='unorm8'?[0,255,1,127,190,32]:kind==='float16'?[0,0x8000,1,0x3c00,0xbc00,0x7bff]:[-0,-2,.00012,1.75,65504,.5];
    const values=Array.from({length:6*channels},(_,index)=>seed[index%seed.length]);
    const data=kind==='unorm8'?new Uint8Array(values):kind==='float16'?new Uint16Array(values):new Float32Array(values);
    const type=kind==='unorm8'?THREE.UnsignedByteType:kind==='float16'?THREE.HalfFloatType:THREE.FloatType;
    const texture=new THREE.DataTexture(data,3,2,format,type);
    texture.generateMipmaps=false;
    const decode=kind==='unorm8'?value=>value/255:kind==='float16'?value=>THREE.DataUtils.fromHalfFloat(value):value=>value;
    captureData(texture,kind+'-'+channels,channels,decode);
    texture.dispose();
  }
  return {textureImageCapture,textureCases,celSamplerCases,
    celSamplerBundle:{celPrograms:cel.programs,celSamplers:cel.samplers}};
}
