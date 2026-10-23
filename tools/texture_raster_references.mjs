// Offline source-renderer evidence; CPU transformUv probes remain separate.
export async function captureTextureRasters(page, references) {
  return page.evaluate(async ({textureImageCapture, textureCases}) => {
    const THREE = await import('three');
    if (!textureCases.length || !textureImageCapture.rgba) throw new Error('Missing original texture raster inputs');
    const width = textureCases[0].probes.length, height = textureCases.length;
    if (!width || textureCases.some(row => row.probes.length !== width)) throw new Error('Inconsistent original texture probe rows');
    const raw = Uint8Array.from(atob(textureImageCapture.rgba), value => value.charCodeAt(0));
    const wraps = {clamp:THREE.ClampToEdgeWrapping, repeat:THREE.RepeatWrapping, mirror:THREE.MirroredRepeatWrapping};
    const renderer = new THREE.WebGLRenderer({antialias:false, alpha:true});
    const target = new THREE.WebGLRenderTarget(width, height, {
      minFilter:THREE.NearestFilter, magFilter:THREE.NearestFilter,
      format:THREE.RGBAFormat, type:THREE.UnsignedByteType, depthBuffer:false, stencilBuffer:false,
    });
    const resources = [], textures = [];
    try {
      renderer.setPixelRatio(1);
      renderer.setSize(width, height, false);
      renderer.toneMapping = THREE.NoToneMapping;
      renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
      target.texture.colorSpace = THREE.LinearSRGBColorSpace;
      renderer.debug.onShaderError = (gl, program) => {
        throw new Error('Original texture raster shader failed: ' + gl.getProgramInfoLog(program));
      };
      const scene = new THREE.Scene();
      const camera = new THREE.OrthographicCamera(0, width, height, 0, .1, 10);
      camera.position.z = 1;
      for (const [row, fixture] of textureCases.entries()) {
        const spec = fixture.spec;
        if (spec.min !== 'nearest' || spec.mag !== 'nearest' || spec.mipmaps ||
          !(spec.wrapS in wraps) || !(spec.wrapT in wraps)) throw new Error('Unsupported original raster fixture sampler');
        const texture = new THREE.DataTexture(raw, textureImageCapture.width, textureImageCapture.height, THREE.RGBAFormat);
        resources.push(texture);
        textures.push(texture);
        texture.wrapS = wraps[spec.wrapS]; texture.wrapT = wraps[spec.wrapT];
        texture.magFilter = THREE.NearestFilter; texture.minFilter = THREE.NearestFilter;
        texture.generateMipmaps = false; texture.flipY = spec.flipY;
        texture.premultiplyAlpha = spec.premultiplyAlpha;
        texture.colorSpace = spec.srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
        texture.channel = spec.channel;
        texture.matrixAutoUpdate = false; texture.matrix.fromArray(spec.matrix);
        texture.needsUpdate = true;
        const positions = [], uv = [], indices = [];
        for (const [column, probe] of fixture.probes.entries()) {
          const first = positions.length / 3;
          positions.push(column,row,0, column+1,row,0, column+1,row+1,0, column,row+1,0);
          for (let corner = 0; corner < 4; corner++) uv.push(...probe.point);
          indices.push(first,first+1,first+2, first,first+2,first+3);
        }
        const geometry = new THREE.BufferGeometry();
        resources.push(geometry);
        geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
        geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
        if (spec.channel) geometry.setAttribute('uv' + spec.channel, new THREE.Float32BufferAttribute(uv, 2));
        geometry.setIndex(indices);
        const material = new THREE.MeshBasicMaterial({map:texture, color:0xffffff, toneMapped:false,
          transparent:true, blending:THREE.NoBlending, depthTest:false, depthWrite:false, fog:false});
        resources.push(material);
        const mesh = new THREE.Mesh(geometry, material);
        mesh.frustumCulled = false;
        scene.add(mesh);
      }
      renderer.setRenderTarget(target);
      renderer.setClearColor(0, 0);
      renderer.clear();
      renderer.render(scene, camera);
      const pixels = new Uint8Array(width * height * 4);
      renderer.readRenderTargetPixels(target, 0, 0, width, height, pixels);
      // Isolate sampler coordinates from transfer-function/output quantization.
      // Keep the unmodified colour-space pass above as independent evidence.
      for (const texture of textures) {
        texture.colorSpace = THREE.NoColorSpace;
        texture.needsUpdate = true;
      }
      renderer.clear();
      renderer.render(scene, camera);
      const samplingPixels = new Uint8Array(width * height * 4);
      renderer.readRenderTargetPixels(target, 0, 0, width, height, samplingPixels);
      const gl = renderer.getContext();
      const error = gl.getError();
      if (error !== gl.NO_ERROR) throw new Error('Original texture raster GL error: ' + error);
      return {width, height, origin:'bottom-left', format:'rgba8', colorSpace:'linear-srgb',
        material:{family:'MeshBasicMaterial', transparent:true, blending:'none', toneMapped:false},
        pixels:Array.from(pixels), rawSampling:{colorSpaceOverride:'none', pixels:Array.from(samplingPixels)},
        rows:textureCases.map(row => ({spec:row.spec, points:row.probes.map(probe => probe.point)}))};
    } finally {
      for (const resource of resources) resource.dispose();
      target.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    }
  }, {textureImageCapture:references.textureImageCapture, textureCases:references.textureCases});
}
