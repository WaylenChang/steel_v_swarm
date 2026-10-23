import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export function readTrainRules(biomes, three) {
  const scalar = (text, pattern) => {
    const match = pattern.exec(text);
    if (!match) throw new Error('Missing original train motion scalar: ' + pattern);
    return Number(match[1]);
  };
  const start = biomes.indexOf('function trainDriver('), end = biomes.indexOf('\n}',start);
  const look = three.indexOf('lookAt( eye, target, up )');
  if (start < 0 || end < 0 || look < 0) throw new Error('Missing original train/lookAt source');
  const driver = biomes.slice(start,end+2), lookAt = three.slice(look,three.indexOf('return this;',look));
  return {lookahead:scalar(driver,/at\(s \+ dirn \* ([\d.]+)\)/),
    turnSquared:scalar(driver,/ahead\.distanceToSquared\(p\) > ([\d.]+)/),
    parallelPerturbation:scalar(lookAt,/_z\.z \+= ([\d.]+)/)};
}

export async function trainReferences(source) {
  const biomes = (await readFile(join(source,'public/js/biomes.js'),'utf8')).replace(/\r\n?/g,'\n');
  const three = await readFile(join(source,'out/forest_review/three.module.js'),'utf8');
  const THREE = await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const {grabFn} = await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const rules = readTrainRules(biomes,three), programs = [];
  const paths = [[[0,0,0],[450,0,0]],
    [[-100,5,-50],[0,5,-50],[0,25,150],[350,15,150]],
    [[0,0,0],[0,0,0],[0,450,0]]];
  for (const points of paths) for (const speed of [17,22]) for (const sample of [0,.5,.999999]) {
    const line = {pts:points.map(point=>new THREE.Vector3(...point))};
    line.total = line.pts.slice(1).reduce((sum,point,i)=>sum+point.distanceTo(line.pts[i]),0);
    const random = Object.create(Math); random.random = ()=>sample;
    const driver = new Function('THREE','Math',grabFn(biomes,'trainDriver')+'\nreturn trainDriver;')(THREE,random);
    const train = new THREE.Group(); train.position.set(4,2,-3);train.rotation.y=.4;train.updateMatrixWorld(true);
    const spec = {...rules,id:1,points,total:line.total,start:sample*line.total,speed,initialFrame:train.matrixWorld.toArray()};
    const update = driver(train,line,speed), frames = [];
    for (const delta of [0,.016,.1,0,line.total/speed,0,.25,line.total/speed,1000,0,.5]) {
      update(delta);train.updateMatrixWorld(true);
      frames.push({delta,matrix:train.matrixWorld.toArray()});
    }
    programs.push({spec,frames});
  }
  return {trainPrograms:programs};
}
