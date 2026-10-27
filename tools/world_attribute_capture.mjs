// Browser capture only. Preserve normalized/interleaved getters and scalar order
// without retaining one temporary JavaScript array for every original vertex.
// Float64 backing storage also avoids the ordinary object heap for large copies.
export function captureWorldAttribute(geometry,name) {
  const attribute=geometry.getAttribute(name);
  if(!attribute)return [];
  if(!Number.isSafeInteger(attribute.itemSize)||attribute.itemSize<1||attribute.itemSize>4
    ||!Number.isSafeInteger(attribute.count)||attribute.count<0)
    throw new Error('Unsupported original world attribute: '+name);
  const getters=['getX','getY','getZ','getW'].slice(0,attribute.itemSize);
  const values=new Float64Array(attribute.count*attribute.itemSize);
  let offset=0;
  for(let index=0;index<attribute.count;index++)for(const getter of getters) {
    const value=attribute[getter](index);
    if(typeof value!=='number'||!Number.isFinite(value))throw new Error('Non-finite original world attribute: '+name);
    values[offset++]=value;
  }
  return values;
}
