import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/js/models.js','public/js/main.js','public/index.html']) {
  const bytes=await readFile(join(source,path));
  if(digest(bytes)!==provenance.inputs[path])throw new Error('Original campaign buffer input changed: '+path);
  sourceInputs[path]=digest(bytes);
}
const text=path=>readFile(join(source,path),'utf8').then(value=>value.replace(/\r\n?/g,'\n'));
const prologue=await text('public/js/prologue.js'),models=await text('public/js/models.js');
const assets=new Function(prologue.match(/const PRELOAD_ASSETS = \[[\s\S]*?\];/)?.[0]+'\nreturn PRELOAD_ASSETS;')();
const manifestText=models.slice(models.indexOf('export const MODEL_MANIFEST ='),models.indexOf('\n\n// ---- 尺度基準'));
const manifest=new Function('window',manifestText.replace('export const','const')+'\nreturn MODEL_MANIFEST;')(undefined);
const bootstrap=(await text('public/index.html'))+'\n'+(await text('public/js/main.js'));
if(/MODEL_MANIFEST_EXTRA/.test(bootstrap)||Object.values(manifest).some(Boolean))throw new Error('Nonempty/custom model warming needs its native source contract');
const begin=prologue.indexOf('export async function bufferGameCache('),end=prologue.indexOf('\n}\n',begin);
if(begin<0||end<0)throw new Error('Missing original cache controller');
const original=prologue.slice(begin,end+3).replace('export async function','async function');
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return{promise,resolve,reject};};
const programs=[];
for(const reject of [false,true])for(const reverse of [false,true]) {
  const images=[],font=deferred(),warm=deferred(),frames=[];
  class Image {set src(path){this.path=path;images.push(this);}}
  const run=new Function('PRELOAD_ASSETS','Image','document','window',original+'\nreturn bufferGameCache;')(
    assets,Image,{fonts:{ready:font.promise}},{__warmModels:()=>warm.promise});
  const task=run(event=>frames.push({...event}));
  const order=reverse?[...images].reverse():images;
  for(const [index,image]of order.entries()) {
    image[reject&&index%2===0?'onerror':'onload']();
    if(index===2){font[reject?'reject':'resolve']();await Promise.resolve();await Promise.resolve();}
  }
  warm[reject?'reject':'resolve']();await task;
  programs.push({reject,reverse,frames});
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const plain=html=>html.replace(/<[^>]*>/g,'');
const element=()=>({innerHTML:'',classList:{add(){},remove(){}}});
const context=Object.assign(Object.create(PrologueIntroController.prototype),{statusEl:element(),skipHintEl:element(),
  bufferPercent:'{percent}',isBufferComplete:false,destroyed:false});
context.renderStatus();
const pending=plain(context.statusEl.innerHTML),pendingHint=plain(context.skipHintEl.innerHTML);
context.isBufferComplete=true;context.renderStatus();
const ready=plain(context.statusEl.innerHTML),readyHint=plain(context.skipHintEl.innerHTML);
let warningMsec=0;
const warning=new Function('setTimeout','return function '+PrologueIntroController.prototype.showBufferWarning.toString())((_callback,delay)=>{warningMsec=delay;});
warning.call(context);
const warningText=plain(context.statusEl.innerHTML);
const skip=[];let finished=0,warnings=0;
context.finish=()=>finished++;
context.showBufferWarning=()=>{warnings++;warning.call(context);};
for(const complete of [false,false,true]) {
  context.isBufferComplete=complete;context.trySkip('probe');
  skip.push({complete,finished,warnings});
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during campaign buffer capture: '+path);
const inputs={};
for(const path of ['tools/campaign_buffer_capture.mjs','tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'data/campaign_buffer.json'),{formatVersion:1,source:{inputs,sourceInputs},
  rules:{assets,modelAssets:[],warningMsec,pending,pendingHint,ready,readyHint,warning:warningText},programs,skip});
console.log('CAMPAIGN_BUFFER_CAPTURE_PASS '+JSON.stringify({assets:assets.length,programs:programs.length}));
