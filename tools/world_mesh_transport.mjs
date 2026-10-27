// Offline, ordered transport. Inline records share a bounded message; numeric
// parts keep their existing frames. Only retired wire copies drive collection.
export function createWorldMeshTransport({split,stringify,encode,sendMesh,sendRows,collect},
  {inlineCount=16,inlineBytes=4*1024*1024,collectionBytes=64*1024*1024}={}) {
  if([split,stringify,encode,sendMesh,sendRows,collect].some(value=>typeof value!=='function')
    ||[inlineCount,inlineBytes,collectionBytes].some(value=>!Number.isSafeInteger(value)||value<=0))
    throw new TypeError('Invalid world mesh transport configuration');
  let count=0,rows=[],rowBytes=4,retiredBytes=0,busy=false,failed=false,finished=false;
  const flush=async()=>{
    if(!rows.length)return;
    const text='['+rows.join(',')+']';
    await sendRows(count-rows.length,text);
    retiredBytes+=text.length*2;
    rows=[];rowBytes=4;
  };
  const run=async action=>{
    if(failed||finished)throw new Error('World mesh transport is closed');
    if(busy){failed=true;throw new Error('Overlapping world mesh transfer');}
    busy=true;
    try {const result=await action();if(failed)throw new Error('World mesh transport failed');return result;}
    catch(error){failed=true;throw error;}
    finally {busy=false;}
  };
  return {
    get count(){return count;},
    append(mesh){return run(async()=>{
      const {header,arrays}=split(mesh,stringify);
      if(!arrays.length) {
        const text=stringify(header),bytes=text.length*2;
        if(rows.length&&(rows.length>=inlineCount||rowBytes+2+bytes>inlineBytes))await flush();
        if(rows.length)rowBytes+=2;
        rows.push(text);rowBytes+=bytes;count++;
        if(rows.length>=inlineCount||rowBytes>=inlineBytes)await flush();
        return;
      }
      await flush();
      const begin=stringify({header,lengths:arrays.map(values=>values.length)});
      await sendMesh('begin',count,0,begin);retiredBytes+=begin.length*2;
      for(let index=0;index<arrays.length;index++) {
        const values=arrays[index],size=typeof values[0]==='number'?65536:64;
        for(let offset=0;offset<values.length;offset+=size) {
          const text=JSON.stringify(encode(values.slice(offset,offset+size)));
          await sendMesh('array-f64',index,offset,text);retiredBytes+=text.length*2;
        }
      }
      await sendMesh('end',count,0,'');count++;
    });},
    collect() {
      if(failed||busy||retiredBytes<collectionBytes)return false;
      retiredBytes=0;
      try {collect();return true;}catch(error){failed=true;throw error;}
    },
    finish() {
      if(failed)return Promise.reject(new Error('World mesh transport is closed'));
      if(finished)return Promise.resolve(count);
      return run(async()=>{await flush();finished=true;return count;});
    },
  };
}
