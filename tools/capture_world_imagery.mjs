import {readFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {selectWorldBundles} from './world_selection.mjs';
import {worldImagerySource} from './world_imagery_source.mjs';
import {WorldImageryStorage} from './world_imagery_storage.mjs';
import {verifyWorldImagery} from './world_imagery_verification.mjs';
import {writeFixtureJson} from './fixture_json.mjs';
import {prepareSourceJson,stringifySourceJson} from './source_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const [bundle,...extra]=process.argv.slice(2);
if(!bundle||extra.length||!/^[a-zA-Z0-9_]+$/.test(bundle))throw new Error('Select one original imagery bundle');
const load=name=>import(pathToFileURL(join(source,name)).href);
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8')),inputs={};
for(const name of ['public/js/terrain.js','public/js/data.js','tools/audit_src.mjs']) {
  inputs[name]=digest(await readFile(join(source,name)));
  if(inputs[name]!==provenance.inputs[name])throw new Error('Original imagery input changed: '+name);
}
const {readSrc,grabFn,grabBlock,grabConst}=await load('tools/audit_src.mjs');
const maps=JSON.parse(await readFile(join(root,'data/maps.json'),'utf8'));
const campaign=JSON.parse(await readFile(join(root,'data/campaign.json'),'utf8'));
const balance=JSON.parse(await readFile(join(root,'data/balance.json'),'utf8'));
const selected=selectWorldBundles([...maps,...campaign.maps],Object.keys(balance.constants.ENV.seasons),['--bundle='+bundle]).get(bundle);
const config=structuredClone(selected.map.variants[String(selected.size)].config);
config.env={...config.env,season:selected.season};
const program=worldImagerySource(readSrc('public','js','terrain.js'),readSrc('public','js','data.js'),grabFn,grabBlock,grabConst);
const original=new Function(program)();
const {chromiumOrNull,chromePath}=await load('tools/pw.mjs');
const chromium=await chromiumOrNull();if(!chromium)throw new Error('Original Chromium is required');
const directory=join(root,'data/world_imagery');await mkdir(directory,{recursive:true});
const storage=new WorldImageryStorage(directory),jobs=new Set(),requests=new Map(),tiles=new Map(),layers=new Map();
let browser,retired=false;
try {
  browser=await chromium.launch({headless:true,executablePath:chromePath()});
  const page=await browser.newPage(),origin='http://source-imagery.invalid';
  page.on('console',message=>{if(message.text().startsWith('SOURCE_IMAGERY '))console.log(message.text());});
  await page.exposeFunction('__sourceImageryBytes',(name,offset,text)=>{
    if(!['raw','display'].includes(name)||!Number.isSafeInteger(offset)||offset<0||typeof text!=='string')
      throw new Error('Invalid original imagery layer');
    const bytes=Buffer.from(text,'base64');
    if(!bytes.length||bytes.toString('base64')!==text)throw new Error('Invalid original imagery byte frame');
    const layer=layers.get(name)||{length:0,parts:[]};
    if(layer.length!==offset)throw new Error('Out-of-order original imagery bytes');
    layer.parts.push(bytes);layer.length+=bytes.length;layers.set(name,layer);
  });
  await page.route('**/*',async route=>{
    if(retired)return route.abort('aborted');
    const url=route.request().url();
    if(url===origin+'/')return route.fulfill({contentType:'text/html',body:'<html></html>'});
    if(!/^https:\/\/server\.arcgisonline\.com\/ArcGIS\/rest\/services\/World_Imagery\/MapServer\/tile\/\d+\/\d+\/\d+$/.test(url))
      return route.abort('blockedbyclient');
    if(!requests.has(url)) {
      const job=(async()=>{
        const response=await fetch(url,{signal:AbortSignal.timeout(15000),redirect:'error',headers:{origin}});
        if(!response.ok)throw new Error('Original imagery HTTP '+response.status);
        const bytes=Buffer.from(await response.arrayBuffer()),contentType=response.headers.get('content-type')||'';
        if(!contentType.startsWith('image/'))throw new Error('Original imagery response is not an image');
        const record=await storage.publish('tile',bytes);
        const allowOrigin=response.headers.get('access-control-allow-origin');
        tiles.set(url,{url,contentType,allowOrigin,etag:response.headers.get('etag'),...record});
        return {bytes,contentType,headers:allowOrigin?{'access-control-allow-origin':allowOrigin}:{}};
      })();
      requests.set(url,job);jobs.add(job);
      const release=()=>{jobs.delete(job);requests.delete(url);};job.then(release,release);
    }
    try {const result=await requests.get(url);await route.fulfill({contentType:result.contentType,body:result.bytes,headers:result.headers});}
    catch(error){console.error('SOURCE_IMAGERY tile-failed '+url+' '+error.message);await route.abort('failed');}
  });
  await page.goto(origin);
  const captured=await page.evaluate(async({program,config,bbox,bounds})=>{
    const original=new Function(program)(),imagery=await original.fetchImagery(bbox,
      value=>console.log('SOURCE_IMAGERY progress '+value));
    if(!imagery.complete)throw new Error('Complete original imagery is unavailable');
    const width=imagery.canvas.width,height=imagery.canvas.height;
    const raw=imagery.canvas.getContext('2d').getImageData(0,0,width,height).data;
    const sample=original.sampler(config.center,imagery,raw),probes=[],queries=[];
    const bits=value=>{const bytes=new Uint8Array(8);new DataView(bytes.buffer).setFloat64(0,value,true);return [...bytes].map(value=>value.toString(16).padStart(2,'0')).join('');};
    const probe=(x,z,tag)=>{
      const point=original.project(config.center,imagery,x,z);
      const result=validOnly=>{
        const rgb=sample(x,z,validOnly);
        return rgb===null?{kind:'null'}:{kind:'rgb',values:rgb.map(value=>value===undefined?'undefined':value)};
      };
      probes.push({tag,pointLE:[bits(x),bits(z)],projectionLE:point.map(bits),ordinary:result(false),validOnly:result(true)});
      queries.push([x,z,result]);
    };
    for(let row=0;row<=16;row++)for(let column=0;column<=16;column++)
      probe(bounds.minX+(bounds.maxX-bounds.minX)*column/16,bounds.minZ+(bounds.maxZ-bounds.minZ)*row/16,'world-grid');
    const xs=[-1,-.5,-.49999999999999994,0,.49999999999999994,.5,.5000000000000001,1.5,width-1,width-.5,width];
    const ys=[-1,-.5,-.49999999999999994,0,.49999999999999994,.5,.5000000000000001,1.5,height-1,height-.5,height];
    for(const px of xs)for(const py of ys) {
      const lng=((px/256+imagery.tx0)/2**imagery.z)*360-180;
      const lat=Math.atan(Math.sinh(Math.PI*(1-2*(py/256+imagery.ty0)/2**imagery.z)))*180/Math.PI;
      probe(...original.llToXZ(lat,lng,config.center),'pixel-boundary');
    }
    for(const [x,z]of [[-0,0],[0,-0],[NaN,0],[0,NaN],[Infinity,0],[0,-Infinity]])probe(x,z,'nonfinite-and-zero');
    const emit=async(name,bytes)=>{for(let offset=0;offset<bytes.length;offset+=65536)
      await window.__sourceImageryBytes(name,offset,btoa(String.fromCharCode(...bytes.subarray(offset,offset+65536))));};
    await emit('raw',raw);
    original.stylizeImagery(imagery.canvas);
    for(let index=0;index<queries.length;index++) {
      const result=queries[index][2];
      if(JSON.stringify(result(false))!==JSON.stringify(probes[index].ordinary)
        ||JSON.stringify(result(true))!==JSON.stringify(probes[index].validOnly))throw new Error('Styling changed raw classification input');
    }
    await emit('display',imagery.canvas.getContext('2d').getImageData(0,0,width,height).data);
    return {width,height,z:imagery.z,tx0:imagery.tx0,ty0:imagery.ty0,complete:imagery.complete,
      constantsLE:Object.fromEntries(Object.entries(original.constants(config.center)).map(([key,value])=>[key,bits(value)])),probes};
  },{program,config,bbox:original.battleBBox(config),bounds:original.battleRect(config)});
  const size=captured.width*captured.height*4;
  if(!Number.isSafeInteger(size)||size<=0||[...layers.values()].some(layer=>layer.length!==size)||layers.size!==2)
    throw new Error('Incomplete original imagery layers');
  const raw=await storage.publish('rgba8',Buffer.concat(layers.get('raw').parts));
  const display=await storage.publish('rgba8',Buffer.concat(layers.get('display').parts));
  for(const [name,hash]of Object.entries(inputs))if(digest(await readFile(join(source,name)))!==hash)throw new Error('Original imagery changed during capture');
  const producer={};
  for(const name of ['tools/capture_world_imagery.mjs','tools/world_imagery_source.mjs','tools/world_imagery_storage.mjs','tools/world_imagery_verification.mjs','tools/source_json.mjs','tools/fixture_json.mjs','tools/world_source_writer.mjs'])
    producer[name]=digest(await readFile(join(root,name)));
  const sourceRecord={inputs,producer,programSha256:digest(program),browser:browser.version(),node:process.versions.node,zlib:process.versions.zlib};
  sourceRecord.inputFingerprint=digest(JSON.stringify(sourceRecord));sourceRecord.assets={};
  sourceRecord.fingerprint=digest(JSON.stringify(sourceRecord));
  const index={formatVersion:1,
    scope:'original-low-resolution-imagery-input-only',identity:{map:selected.map.id,teamSize:selected.size,season:selected.season},
    configSha256:digest(JSON.stringify(config)),source:sourceRecord,
    ...captured,raw,display,tiles:[...tiles.values()].sort((a,b)=>a.url.localeCompare(b.url))};
  index.fingerprint=digest(stringifySourceJson(index));
  await verifyWorldImagery(index,directory);
  await writeFixtureJson(join(directory,bundle+'.json'),prepareSourceJson(index));
  console.log('SOURCE_IMAGERY_CAPTURE_PASS '+JSON.stringify({bundle,width:captured.width,height:captured.height,tiles:tiles.size,probes:captured.probes.length}));
} finally {
  retired=true;
  try {if(browser)await browser.close();}
  finally {await Promise.allSettled([...jobs]);await storage.dispose();}
}
