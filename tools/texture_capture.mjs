// Browser-only migration codec shared by model and world exporters.
export function captureTextureImage(texture, retainBytes = false) {
  if (texture.isVideoTexture || texture.isCompressedTexture || texture.isCubeTexture || texture.isDepthTexture)
    throw new Error('Unsupported original texture image type: ' + texture.type);
  const levels = texture.mipmaps ?? [];
  if (!Array.isArray(levels)) throw new Error('Invalid original manual texture mip chain');
  if (levels.length && texture.generateMipmaps) throw new Error('Conflicting original manual/automatic mip generation');
  const image = levels.length ? levels[0] : texture.image;
  if (!image || !Number.isInteger(image.width) || !Number.isInteger(image.height) || image.width <= 0 || image.height <= 0)
    throw new Error('Original texture image is not ready');
  if (image.data && (!(image.data instanceof Uint8Array) && !(image.data instanceof Uint8ClampedArray)
    || image.data.length !== image.width * image.height * 4))
    throw new Error('Unsupported original texture pixel format');
  let captured;
  if (retainBytes && image.data) {
    const chunks = [];
    for (let offset=0;offset<image.data.length;offset+=8192)
      chunks.push(String.fromCharCode(...image.data.subarray(offset,offset+8192)));
    captured = {width:image.width,height:image.height,rgba:btoa(chunks.join(''))};
  } else {
    const canvas = document.createElement('canvas');
    canvas.width = image.width; canvas.height = image.height;
    const context = canvas.getContext('2d');
    if (image.data) context.putImageData(new ImageData(new Uint8ClampedArray(image.data),image.width,image.height),0,0);
    else context.drawImage(image,0,0);
    captured = {width:image.width,height:image.height,png:canvas.toDataURL('image/png').split(',')[1]};
  }
  if (levels.length) {
    const count = Math.floor(Math.log2(Math.max(image.width,image.height))) + 1;
    if (levels.length !== count) throw new Error('Incomplete original manual texture mip chain');
    captured.mipmaps = levels.slice(1).map((level,index)=>{
      if (level.width !== Math.max(1,Math.floor(image.width/2**(index+1)))
        || level.height !== Math.max(1,Math.floor(image.height/2**(index+1))))
        throw new Error('Invalid original manual texture mip extent');
      return captureTextureImage({image:level,mipmaps:[],type:texture.type},retainBytes);
    });
  }
  return captured;
}

export function describeSourceTexture(texture, THREE, allowDataFormat = false) {
  if (texture.mapping !== THREE.UVMapping) throw new Error('Unsupported original albedo texture mapping');
  if (!allowDataFormat && texture.image?.data && texture.format !== THREE.RGBAFormat) throw new Error('Unsupported original non-RGBA data texture');
  if (texture.matrixAutoUpdate) texture.updateMatrix();
  if (!texture.matrix.elements.every(Number.isFinite)) throw new Error('Non-finite original texture transform');
  const wrapping = value => {
    if (value === THREE.ClampToEdgeWrapping) return 'clamp';
    if (value === THREE.RepeatWrapping) return 'repeat';
    if (value === THREE.MirroredRepeatWrapping) return 'mirror';
    throw new Error('Unsupported original texture wrap');
  };
  const filters = new Map([[THREE.NearestFilter,'nearest'],[THREE.LinearFilter,'linear'],
    [THREE.NearestMipmapNearestFilter,'nearest_mipmap_nearest'],[THREE.NearestMipmapLinearFilter,'nearest_mipmap_linear'],
    [THREE.LinearMipmapNearestFilter,'linear_mipmap_nearest'],[THREE.LinearMipmapLinearFilter,'linear_mipmap_linear']]);
  if (!filters.has(texture.minFilter) || !filters.has(texture.magFilter)) throw new Error('Unsupported original texture filter');
  if (![THREE.NearestFilter,THREE.LinearFilter].includes(texture.magFilter)) throw new Error('Invalid original texture magnification filter');
  if (![THREE.SRGBColorSpace,THREE.LinearSRGBColorSpace,THREE.NoColorSpace].includes(texture.colorSpace))
    throw new Error('Unsupported original texture colour space');
  return {matrix:texture.matrix.toArray(),flipY:texture.flipY,channel:texture.channel,
    wrapS:wrapping(texture.wrapS),wrapT:wrapping(texture.wrapT),
    min:filters.get(texture.minFilter),mag:filters.get(texture.magFilter),mipmaps:!!texture.generateMipmaps,
    ...(texture.mipmaps.length?{manualMipmaps:true}:{}),
    srgb:texture.colorSpace === THREE.SRGBColorSpace,anisotropy:texture.anisotropy,
    premultiplyAlpha:!!texture.premultiplyAlpha};
}

export function captureTextureUV(geometry, channel = 0) {
  const attribute = geometry.getAttribute(channel === 0 ? 'uv' : 'uv' + channel);
  if (!attribute) return [];
  if (attribute.itemSize !== 2) throw new Error('Unsupported original texture coordinate size');
  const values = Array.from({length:attribute.count},(_,index)=>[attribute.getX(index),attribute.getY(index)]).flat();
  if (!values.every(Number.isFinite)) throw new Error('Non-finite original texture coordinates');
  return values;
}
