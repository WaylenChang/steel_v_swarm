import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
async function responseBytes(entry,path){
  let bytes;
  try {bytes=await readFile(path);}catch(error){if(error.code!=='ENOENT')throw error;const response=await fetch(entry.url);if(!response.ok)throw new Error('Font response failed: '+entry.url);bytes=Buffer.from(await response.arrayBuffer());if(digest(bytes)!==entry.sha256)throw new Error('Pinned font response changed: '+entry.url);await mkdir(resolve(path,'..'),{recursive:true});await writeFile(path,bytes);}
  if(digest(bytes)!==entry.sha256)throw new Error('Captured font response changed: '+entry.url);
  return bytes;
}
const layoutBytes=await readFile(join(root,'tests/fixtures/dialogue_layout.json'));
const layout=JSON.parse(layoutBytes),cached=new Map();
for(const entry of layout.fonts)cached.set(entry.url,await responseBytes(entry,join(root,'build/dialogue_layout',entry.path)));
for(const [file,hash]of Object.entries(layout.source.sourceInputs))if(digest(await readFile(join(source,file)))!==hash)throw new Error('Source changed: '+file);
const stylesheet=layout.fonts.find(font=>font.path.endsWith('.css')),css=cached.get(stylesheet.url).toString('utf8');
const allowed=new Set([...css.matchAll(/src:\s*url\(([^)]+)\)/g)].map(match=>match[1]));
const {STORY_TALK}=await import(pathToFileURL(join(source,'public/js/storytalk.js')).href);
const {CHARACTERS}=await import(pathToFileURL(join(source,'public/js/data.js')).href);
const cases=[],seen=new Set();
const add=(text,size,weight)=>{const key=JSON.stringify([text,size,weight]);if(!seen.has(key)){seen.add(key);cases.push({text,size,weight});}};
for(const chapter of Object.values(STORY_TALK))for(const side of Object.values(chapter))for(const scene of Object.values(side)){
  for(const size of [11,12]){add(scene.title,size,700);add(scene.note,size,400);}
  for(const line of scene.lines){const hero=CHARACTERS[line.ch];add(`「${hero.code}」${hero.name}`,12,400);for(const size of [13,14,15])add(line.t,size,400);}
}
const glyphs=[...new Set(cases.flatMap(item=>Array.from(item.text).map(character=>character.codePointAt(0))))].sort((a,b)=>a-b);
const preload=String.fromCodePoint(...glyphs),output=join(root,'build/dialogue_fonts');await mkdir(output,{recursive:true});
const responses=new Map(),pending=[];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();if(!chromium)throw new Error('Original Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let metrics;
try {
  const page=await browser.newPage();
  page.on('response',response=>{if(!allowed.has(response.url())||!response.ok())return;pending.push((async()=>{const bytes=await response.body(),sha256=digest(bytes),path=sha256+'.woff2';await writeFile(join(output,path),bytes);responses.set(response.url(),{url:response.url(),sha256,path,bytes:bytes.length});})());});
  await page.route('**/*',async route=>{const url=route.request().url();if(!allowed.has(url))return route.abort();
    if(cached.has(url))return route.fulfill({contentType:'font/woff2',body:cached.get(url)});
    if(new URL(url).hostname!=='fonts.gstatic.com')throw new Error('Unexpected source font URL');
    return route.continue();});
  await page.setContent('<style>'+css+'</style>');
  metrics=await page.evaluate(async({cases,preload,language})=>{
    document.documentElement.lang=language;
    for(const weight of [400,700])await document.fonts.load(`${weight} 15px "Noto Sans TC"`,preload);
    const canvas=document.createElement('canvas'),context=canvas.getContext('2d');
    if(!('lang' in context))throw new Error('Canvas language selection is required for source font metrics');
    context.lang=language;
    return cases.map(item=>{context.font=`${item.weight} ${item.size}px "Noto Sans TC"`;const result=context.measureText(item.text);
      return {...item,width:result.width,ink:[result.actualBoundingBoxLeft,result.actualBoundingBoxRight,result.actualBoundingBoxAscent,result.actualBoundingBoxDescent]};});
  },{cases,preload,language:layout.host.language});
  await Promise.all(pending);await page.close();
} finally {await browser.close();}
if(responses.size===0)throw new Error('No original Noto fonts loaded');
const file='tools/dialogue_fonts_capture.mjs',inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n')),'tests/fixtures/dialogue_layout.json':digest(layoutBytes)};
for(const [path,hash]of Object.entries(layout.source.sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Source changed during font capture: '+path);
const identity={inputs,sourceInputs:layout.source.sourceInputs,language:layout.host.language,stylesheet:{url:stylesheet.url,sha256:stylesheet.sha256}};
const fonts=[...responses.values()].sort((a,b)=>a.url.localeCompare(b.url));
const licencePath=join(output,'OFL.txt'),licenceUrl='https://raw.githubusercontent.com/google/fonts/main/ofl/notosanstc/OFL.txt';
let licence;
try {licence=await readFile(licencePath);}catch(error){if(error.code!=='ENOENT')throw error;const response=await fetch(licenceUrl);if(!response.ok)throw new Error('Original font licence failed');licence=Buffer.from(await response.arrayBuffer());await writeFile(licencePath,licence);}
identity.licence={url:licenceUrl,sha256:digest(licence),text_sha256:digest(licence.toString('utf8').replace(/\r\n?/g,'\n'))};
await writeFixtureJson(join(root,'data/dialogue_fonts.json'),{formatVersion:1,source:identity,weights:[400,700],glyphs,fonts});
await writeFixtureJson(join(root,'tests/fixtures/dialogue_fonts.json'),{formatVersion:1,source:identity,browser:browser.version(),weights:[400,700],glyphs,fonts,metrics});
console.log('DIALOGUE_FONTS_REFERENCES_PASS fonts='+fonts.length+' glyphs='+glyphs.length+' metrics='+metrics.length);
