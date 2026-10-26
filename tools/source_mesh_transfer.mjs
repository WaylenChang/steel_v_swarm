// Offline transfer only. Equality includes rank, row widths and signed zero.
export function sourceMeshTransfer(mesh,stringify) {
  if(typeof stringify!=='function')throw new TypeError('Source mesh transfer requires its numeric JSON encoder');
  const arrays=[],lengths=new Map();
  const equal=(first,second)=>{
    for(let index=0;index<first.length;index++) {
      const a=first[index],b=second[index];
      if(typeof a==='number'&&typeof b==='number') {
        if(!Object.is(a,b))return false;
      } else if(Array.isArray(a)&&Array.isArray(b)&&a.length===b.length) {
        for(let column=0;column<a.length;column++)
          if(typeof a[column]!=='number'||typeof b[column]!=='number'||!Object.is(a[column],b[column]))return false;
      } else return false;
    }
    return true;
  };
  const header=JSON.parse(stringify(mesh,(_key,value)=>{
    if(value&&typeof value==='object'&&(Object.hasOwn(value,'$sourceArray')||Object.hasOwn(value,'$sourceNumericArray')))
      throw new Error('Reserved source mesh storage property');
    if(!Array.isArray(value)||value.length<=4096)return value;
    const candidates=lengths.get(value.length)||[];
    for(const id of candidates)if(equal(arrays[id],value))return {$sourceArray:id};
    const id=arrays.length;arrays.push(value);candidates.push(id);lengths.set(value.length,candidates);
    return {$sourceArray:id};
  }));
  return {header,arrays};
}
