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
for(const path of ['public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','public/index.html']){
  const hash=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==hash)throw new Error('Original cinematic input changed: '+path);
  sourceInputs[path]=hash;
}
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const proto=PrologueIntroController.prototype;
const plain=html=>html.replace(/<[^>]*>/g,'');
const element=()=>{
  const classes=new Set();
  return {innerHTML:'',style:{},scrollTop:0,classList:{add:name=>classes.add(name),remove:name=>classes.delete(name)},classes};
};
const programs=[];
for(const kind of ['prologue','chapter']){
  const nodes=new Map();
  globalThis.document={getElementById:id=>{
    if(!nodes.has(id))nodes.set(id,element());
    return nodes.get(id);
  }};
  const controller=new PrologueIntroController(kind==='chapter'?{scenes:[{id:'chapter'}],isPrologue:false}:{});
  const frames=[],callbacks=[];
  controller.initDOM=()=>{};
  controller.setScene=()=>{};
  controller.renderStatus=function(){
    proto.renderStatus.call(this);
    frames.push({complete:this.isBufferComplete,percent:this.bufferPercent,status:plain(this.statusEl.innerHTML),
      hint:plain(this.skipHintEl.innerHTML),statusClasses:[...this.statusEl.classes],hintClasses:[...this.skipHintEl.classes]});
  };
  const play=new Function('bufferGameCache','requestAnimationFrame','performance',
    'return function '+proto.play.toString())(
      callback=>{callbacks.push(callback);return new Promise(()=>{});},()=>1,{now:()=>1000});
  play.call(controller);
  if(kind==='prologue'){
    if(callbacks.length!==1)throw new Error('Original prologue did not start buffering');
    callbacks[0]({pct:58,ready:false});
    callbacks[0]({pct:100,ready:true});
  }else if(callbacks.length!==0)throw new Error('Original chapter unexpectedly started buffering');
  programs.push({kind,isPrologue:controller.isPrologue,bufferRequests:callbacks.length,frames});
}
for(const [path,expected]of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Original cinematic input changed during capture: '+path);
const generator='tools/campaign_chapter_status_capture.mjs';
const inputs={};
for(const path of [generator,'tools/fixture_json.mjs'])
  inputs[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/campaign_chapter_status.json'),
  {formatVersion:1,source:{inputs,sourceInputs},programs});
console.log('CAMPAIGN_CHAPTER_STATUS_CAPTURE_PASS programs='+programs.length);
