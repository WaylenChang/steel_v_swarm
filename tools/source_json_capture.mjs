import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {stringifySourceJson,prepareSourceJson} from './source_json.mjs';
import {WorldSourceWriter} from './world_source_writer.mjs';
import {sourceMeshTransfer} from './source_mesh_transfer.mjs';
import {encodeSourceNumericPart,decodeSourceNumericPart} from './source_numeric_transfer.mjs';
import {writeFixtureJson} from './fixture_json.mjs';
import {verifyWorldStorage} from './world_source.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const directory=join(root,'artifacts/sol/source-json'),resourceRoot='res://artifacts/sol/source-json';
const digest=value=>createHash('sha256').update(value).digest('hex');
const library='out/forest_review/three.module.js',bytes=await readFile(join(source,library));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
if(provenance.inputs[library]!==digest(bytes))throw new Error('Original source numeric geometry changed');
await mkdir(directory,{recursive:true});
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();if(!chromium)throw new Error('Original Chromium is required');
const writer=new WorldSourceWriter(directory,resourceRoot);
const previous=process.cwd();let browser;
try {
  process.chdir(directory);
  browser=await chromium.launch({headless:true,executablePath:chromePath()});
  const version=browser.version(),page=await browser.newPage();
  const cases=await page.evaluate(async({library,stringifier,transferSource,numericSource})=>{
    const THREE=await import(library),encode=new Function('return ('+stringifier+');')();
    const transfer=new Function('return ('+transferSource+');')();
    const numeric=new Function('return ('+numericSource+');')();
    const results=[];
    for(const [width,height]of [[8,6],[64,32]]) {
      const geometry=new THREE.SphereGeometry(1,width,height);
      const mesh={name:'sphere_'+width,positions:[...geometry.attributes.position.array],normal:[...geometry.attributes.normal.array],
        matrix:[...new THREE.Matrix4().makeRotationX(0).elements]};
      const expected={},negativeZero={};
      for(const key of ['positions','normal','matrix']) {
        const bytes=new Uint8Array(new Float64Array(mesh[key]).buffer),parts=[];
        for(let offset=0;offset<bytes.length;offset+=8192)parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
        expected[key]=btoa(parts.join(''));negativeZero[key]=mesh[key].filter(value=>Object.is(value,-0)).length;
      }
      const probe=transfer({primary:mesh.positions,copy:mesh.positions.slice()},encode);
      const arrayCount=mesh.positions.length>4096?1:0;
      if(probe.arrays.length!==arrayCount||arrayCount&&probe.header.primary.$sourceArray!==probe.header.copy.$sourceArray)
        throw new Error('Browser source geometry transfer failed exact duplicate admission');
      const binary=Object.fromEntries(Object.keys(expected).map(key=>[key,numeric(mesh[key])]));
      const binaryMatrix=numeric([mesh.matrix,mesh.matrix.slice()]);
      results.push({payload:encode(mesh),expected,negativeZero,transferArrays:probe.arrays.length,binary,binaryMatrix});geometry.dispose();
    }
    return results;
  },{library:'data:text/javascript;base64,'+bytes.toString('base64'),stringifier:stringifySourceJson.toString(),transferSource:sourceMeshTransfer.toString(),numericSource:encodeSourceNumericPart.toString()});
  await browser.close();browser=null;process.chdir(previous);
  for(const [index,item]of cases.entries()) {
    const mesh=JSON.parse(item.payload);
    for(const key of Object.keys(item.expected)) {
      const actual=Buffer.from(new Float64Array(mesh[key]).buffer);
      if(!actual.equals(Buffer.from(item.expected[key],'base64')))throw new Error('Source numeric transfer changed: '+key);
      const binary=decodeSourceNumericPart(item.binary[key]);
      if(binary.matrix||binary.rows!==mesh[key].length||!binary.bytes.equals(Buffer.from(item.expected[key],'base64')))
        throw new Error('Source binary numeric transfer changed: '+key);
    }
    const matrix=decodeSourceNumericPart(item.binaryMatrix),matrixWords=Buffer.from(item.expected.matrix,'base64');
    if(!matrix.matrix||matrix.rows!==2||matrix.width!==mesh.matrix.length||!matrix.bytes.equals(Buffer.concat([matrixWords,matrixWords])))
      throw new Error('Source binary matrix transfer changed');
    item.metadata={matrix:mesh.matrix};
    const {header,arrays}=sourceMeshTransfer(mesh,stringifySourceJson);
    await writer.begin(index,header,arrays.map(array=>array.length));
    for(let part=0;part<arrays.length;part++) {
      const key=Object.keys(item.binary).find(key=>mesh[key]===arrays[part]);
      if(!key)throw new Error('Missing original binary numeric probe');
      await writer.partEncoded(part,0,item.binary[key]);
    }
    await writer.end(index);
  }
  const manifest=await writer.finish();
  await verifyWorldStorage(manifest,directory,resourceRoot);
  if(digest(await readFile(join(source,library)))!==digest(bytes))throw new Error('Source changed during numeric capture');
  const inputs={};
  for(const file of ['tools/source_json_capture.mjs','tools/source_json.mjs','tools/source_mesh_transfer.mjs','tools/source_numeric_transfer.mjs','tools/world_source_writer.mjs','tools/fixture_json.mjs'])
    inputs[file]=digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'));
  await writeFixtureJson(join(directory,'fixture.json'),prepareSourceJson({formatVersion:1,source:{inputs,sourceInputs:{[library]:digest(bytes)},chromium:version},resourceRoot,manifest,cases}));
  console.log('SOURCE_JSON_CAPTURE_PASS '+JSON.stringify({cases:cases.length,binaryParts:cases.reduce((sum,item)=>sum+Object.keys(item.binary).length+1,0),negativeZero:cases.map(item=>item.negativeZero)}));
} finally {
  try {if(browser)await browser.close();}finally {process.chdir(previous);await writer.dispose();}
}
