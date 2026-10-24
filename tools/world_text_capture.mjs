export function instrumentWorldTextCapture(source) {
  const seam='mesh.userData.signTex = tex;';
  if(source.split(seam).length!==2||source.includes('nativeWorldText'))
    throw new Error('Missing or repeated original world-text capture seam');
  return source.replace(seam,seam+`
    mesh.userData.nativeWorldText = JSON.parse(JSON.stringify({
      language: visualPref('worldTextLang'), scale: this.scale, reserved: this.reserved,
      atlas: {width: cv.width, height: cv.height}, items: this.items,
      styles: Object.fromEntries([...new Set(this.items.map(item => item.style))]
        .map(style => [style, SIGN_STYLES[style] || SIGN_STYLES.stone])),
    }));`);
}

export function captureWorldTextMesh(mesh) {
  const data=mesh.userData||{};
  if(data.isOutline)return null;
  const glow=mesh.geometry?.getAttribute('signGlow');
  if(data.signCount==null&&!glow)return null;
  const captured=data.nativeWorldText;
  if(!captured||!Array.isArray(captured.items)||!captured.styles||!captured.atlas)
    throw new Error('Missing original world-text constructor metadata');
  if(!Number.isInteger(data.signCount)||!Number.isInteger(data.signDropped)||data.signCount<0||data.signDropped<0
    ||data.signCount+data.signDropped!==captured.items.length)
    throw new Error('Invalid original world-text admission counts');
  const image=data.signTex?.image;
  if(!image||image.width!==captured.atlas.width||image.height!==captured.atlas.height)
    throw new Error('Original world-text atlas dimensions changed');
  const position=mesh.geometry.getAttribute('position');
  if(!glow||glow.itemSize!==1||glow.count!==position?.count)
    throw new Error('Missing original per-vertex world-text glow');
  const values=Array.from({length:glow.count},(_,index)=>glow.getX(index));
  if(values.some(value=>!Number.isFinite(value)))throw new Error('Nonfinite original world-text glow');
  return {...JSON.parse(JSON.stringify(captured)),count:data.signCount,dropped:data.signDropped,glow:values};
}
