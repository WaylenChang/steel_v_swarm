import {createReadStream} from 'node:fs';
import {readFile,stat} from 'node:fs/promises';
import {compose} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import json from 'stream-json';
import Ignore from 'stream-json/filters/Ignore.js';
import Pick from 'stream-json/filters/Pick.js';
import StreamValues from 'stream-json/streamers/StreamValues.js';
import StreamArray from 'stream-json/streamers/StreamArray.js';

// Structure/reference tools consume completed world metadata, not render meshes.
export async function readWorldHeader(path) {
  // Use the native parser for bounded bundles; reserve token streaming for giant captures.
  if((await stat(path)).size<=128*1024*1024) {
    const result=JSON.parse(await readFile(path,'utf8'));
    if(!result||typeof result!=='object'||Array.isArray(result))throw new Error('Invalid source world root: '+path);
    delete result.meshes;
    return result;
  }
  const stream=compose(createReadStream(path),json.parser({streamValues:false}),Ignore.ignore({filter:'meshes'}),StreamValues.streamValues());
  let result;
  for await(const {value}of stream){
    if(result!==undefined)throw new Error('Multiple source world roots: '+path);
    result=value;
  }
  if(!result||typeof result!=='object'||Array.isArray(result))throw new Error('Invalid source world root: '+path);
  return result;
}

export async function* readLegacyWorldMeshes(path) {
  const stream=StreamArray.streamArray({highWaterMark:1});
  const completion=pipeline(createReadStream(path),json.parser({streamValues:false}),Pick.pick({filter:'meshes'}),stream);
  completion.catch(()=>{});
  let index=0;
  try {
    for await(const row of stream){
      if(row.key!==index++)throw new Error('Out-of-order original world mesh');
      yield row.value;
    }
    await completion;
  } finally {
    stream.destroy();
    await completion.catch(()=>{});
  }
}
