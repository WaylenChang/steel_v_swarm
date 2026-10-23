import {captureTextureImage, describeSourceTexture} from './texture_capture.mjs';

// Execute the source Canvas2D downsampler; never reconstruct authored mips in Node.
export async function captureTextureMips(page) {
  return page.evaluate(async ({captureSource, describeSource}) => {
    const THREE = await import('three');
    const {buildMipChain, attachMipChain} = await import('/js/tex.js');
    const capture = new Function('return (' + captureSource + ')')();
    const describe = new Function('return (' + describeSource + ')')();
    const cases = [];
    const renderer = new THREE.WebGLRenderer({antialias:false,alpha:true});
    const scene = new THREE.Scene(), camera = new THREE.Camera();
    const material = new THREE.ShaderMaterial({glslVersion:THREE.GLSL3,depthTest:false,depthWrite:false,
      blending:THREE.NoBlending,uniforms:{source:{value:null},level:{value:0},extent:{value:new THREE.Vector2()},span:{value:new THREE.Vector2()}},
      vertexShader:'void main(){gl_Position=vec4(position,1.0);}',
      fragmentShader:'uniform sampler2D source;uniform float level;uniform vec2 extent;uniform vec2 span;out vec4 result;void main(){result=textureLod(source,gl_FragCoord.xy/extent*span,level);}'});
    const geometry = new THREE.PlaneGeometry(2,2);
    scene.add(new THREE.Mesh(geometry,material));
    renderer.debug.onShaderError=(gl,program)=>{throw new Error('Original authored mip raster shader failed: '+gl.getProgramInfoLog(program));};
    try {
    for (const [width, height] of [[8,4], [3,5], [1,8], [1,1]]) {
      const canvas = document.createElement('canvas');
      canvas.width = width; canvas.height = height;
      const context = canvas.getContext('2d');
      const pixels = context.createImageData(width,height);
      for (let i=0;i<width*height;i++) pixels.data.set([(i*71+13)%256,(i*37+29)%256,(i*19+91)%256,255],i*4);
      context.putImageData(pixels,0,0);
      const chain = buildMipChain(canvas);
      const levels = chain.map(image=>({width:image.width,height:image.height,
        bytes:Array.from(image.getContext('2d').getImageData(0,0,image.width,image.height).data)}));
      for (const flipY of [false,true]) {
        const texture = attachMipChain(new THREE.CanvasTexture(canvas),chain);
        texture.colorSpace = THREE.SRGBColorSpace;
        texture.flipY = flipY;
        const fixture={label:`source-canvas-${width}x${height}-flip-${flipY}`,
          capture:capture(texture),spec:{...describe(texture,THREE),image:0},levels,nativeVariants:[]};
        // Raw sampling isolates authored texels from colour-space transfer functions.
        texture.colorSpace=THREE.NoColorSpace;
        texture.minFilter=THREE.NearestMipmapNearestFilter;
        texture.magFilter=THREE.NearestFilter;
        for(const [s,t,repeatX,repeatY] of [[false,false,1,1],...(width===8&&height===4?[[true,true,1,1],[true,false,4,1]]:[])]) {
          texture.wrapS=s?THREE.MirroredRepeatWrapping:THREE.RepeatWrapping;
          texture.wrapT=t?THREE.MirroredRepeatWrapping:THREE.RepeatWrapping;
          texture.needsUpdate=true;
          const nativeWidth=width*(s?2:1)*repeatX,nativeHeight=height*(t?2:1)*repeatY;
          const variant={spec:{...fixture.spec,wrapS:s?'mirror':'repeat',wrapT:t?'mirror':'repeat',
            nativeTileSpan:[repeatX,repeatY]},levels:[],colorSpaceOverride:'none'};
          material.uniforms.source.value=texture;
          material.uniforms.span.value.set((s?2:1)*repeatX,(t?2:1)*repeatY);
          for(let level=0;level<=Math.floor(Math.log2(Math.max(nativeWidth,nativeHeight)));level++) {
            const w=Math.max(1,Math.floor(nativeWidth/2**level)),h=Math.max(1,Math.floor(nativeHeight/2**level));
            const target=new THREE.WebGLRenderTarget(w,h,{minFilter:THREE.NearestFilter,magFilter:THREE.NearestFilter,depthBuffer:false,stencilBuffer:false});
            try {
              material.uniforms.level.value=level;
              material.uniforms.extent.value.set(w,h);
              renderer.setRenderTarget(target);renderer.render(scene,camera);
              const pixels=new Uint8Array(w*h*4);
              renderer.readRenderTargetPixels(target,0,0,w,h,pixels);
              const error=renderer.getContext().getError();
              if(error)throw new Error('Original manual mip sampling failed: '+error);
              variant.levels.push({width:w,height:h,bytes:Array.from(pixels)});
            } finally {renderer.setRenderTarget(null);target.dispose();}
          }
          fixture.nativeVariants.push(variant);
        }
        cases.push(fixture);
        texture.dispose();
      }
    }
    return cases;
    } finally {geometry.dispose();material.dispose();renderer.dispose();}
  }, {captureSource:captureTextureImage.toString(),describeSource:describeSourceTexture.toString()});
}
