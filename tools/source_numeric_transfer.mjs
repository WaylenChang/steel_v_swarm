// Offline browser transport. Storage remains the existing little-endian float64 format.
export function encodeSourceNumericPart(values) {
  if(!Array.isArray(values)||!values.length)throw new Error('Empty source numeric transfer');
  const matrix=Array.isArray(values[0]),width=matrix?values[0].length:1;
  if(!width||matrix&&values.some(row=>!Array.isArray(row)||row.length!==width))
    throw new Error('Inconsistent source numeric transfer shape');
  if(values.length>Math.floor(268435455/width))throw new Error('Invalid source numeric transfer extent');
  const flat=matrix?values.flat():values;
  if(flat.length!==values.length*width)throw new Error('Unsupported source numeric transfer value');
  for(let index=0;index<flat.length;index++)
    if(typeof flat[index]!=='number'||!Number.isFinite(flat[index]))throw new Error('Unsupported source numeric transfer value');
  if(new Uint8Array(new Uint16Array([1]).buffer)[0]!==1)
    throw new Error('Source numeric transfer requires a little-endian browser');
  const bytes=new Uint8Array(new Float64Array(flat).buffer),parts=[];
  for(let offset=0;offset<bytes.length;offset+=8192)
    parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
  return {encoding:'f64-le-base64',shape:matrix?[values.length,width]:[values.length],data:btoa(parts.join(''))};
}

export function decodeSourceNumericPart(value) {
  if(value===null||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==3
    ||value.encoding!=='f64-le-base64'||!Array.isArray(value.shape)||![1,2].includes(value.shape.length)
    ||typeof value.data!=='string')throw new Error('Invalid source numeric transfer declaration');
  let count=1;
  for(const extent of value.shape) {
    if(!Number.isSafeInteger(extent)||extent<=0||extent>Math.floor(268435455/count))
      throw new Error('Invalid source numeric transfer extent');
    count*=extent;
  }
  const expected=count*8;
  if(value.data.length!==4*Math.ceil(expected/3)||!/^[A-Za-z0-9+/]*={0,2}$/.test(value.data))
    throw new Error('Invalid source numeric transfer encoding');
  const bytes=Buffer.from(value.data,'base64');
  if(bytes.length!==expected||bytes.toString('base64')!==value.data)
    throw new Error('Invalid source numeric transfer encoding');
  for(let offset=0;offset<bytes.length;offset+=8)
    if(!Number.isFinite(bytes.readDoubleLE(offset)))throw new Error('Unsupported source numeric transfer value');
  return {bytes,rows:value.shape[0],width:value.shape.length===2?value.shape[1]:1,matrix:value.shape.length===2};
}
