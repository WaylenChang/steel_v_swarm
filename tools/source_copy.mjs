import {cp,lstat} from 'node:fs/promises';
import {basename} from 'node:path';

// Godot descriptors belong to the destination project, not to authored assets.
// A source checkout may contain them after an editor scan; never import their
// resource UIDs or source paths into another project.
export async function copySourceTree(from,to,{onFile,...options}={}) {
  await cp(from,to,{...options,filter:async path=>{
    if(basename(path).endsWith('.import'))return false;
    const info=await lstat(path);
    if(info.isSymbolicLink())throw new Error('Cannot copy a symbolic source asset: '+path);
    if(info.isFile()&&onFile)await onFile(path);
    return true;
  }});
}
