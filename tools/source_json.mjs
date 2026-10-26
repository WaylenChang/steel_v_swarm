// Offline capture JSON preserves finite number bits, including the sign of zero.
export function stringifySourceJson(value,replacer) {
  if(typeof JSON.rawJSON!=='function')throw new Error('Source capture requires native JSON.rawJSON support');
  return JSON.stringify(value,function(key,item){
    const result=replacer?replacer.call(this,key,item):item;
    return Object.is(result,-0)?JSON.rawJSON('-0'):result;
  });
}

// Adapt plain captured metadata for the shared streaming publisher without mutating its caller.
export function prepareSourceJson(value,ancestors=new Set()) {
  if(typeof JSON.rawJSON!=='function')throw new Error('Source capture requires native JSON.rawJSON support');
  if(Object.is(value,-0))return JSON.rawJSON('-0');
  if(value===null||typeof value!=='object'||JSON.isRawJSON(value))return value;
  if(!Array.isArray(value)&&Object.getPrototypeOf(value)!==Object.prototype&&Object.getPrototypeOf(value)!==null)
    throw new TypeError('Source publication requires plain captured JSON values');
  if(typeof value.toJSON==='function')throw new TypeError('Source publication requires plain captured JSON values');
  if(ancestors.has(value))throw new TypeError('Circular captured source JSON');
  ancestors.add(value);
  try {
    const keys=Array.isArray(value)?null:Object.keys(value);
    const length=keys?keys.length:value.length;
    let result=value;
    for(let index=0;index<length;index++) {
      const key=keys?keys[index]:index,original=value[key],encoded=prepareSourceJson(original,ancestors);
      if(!Object.is(original,encoded)) {
        if(result===value)result=Array.isArray(value)?value.slice():{...value};
        result[key]=encoded;
      }
    }
    return result;
  } finally {ancestors.delete(value);}
}
