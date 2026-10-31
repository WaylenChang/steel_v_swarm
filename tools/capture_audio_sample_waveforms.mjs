import assert from 'node:assert/strict';
import {readFile,mkdir,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve,relative,isAbsolute} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {encodeSourceNumericPart as encode} from './source_numeric_transfer.mjs';
import {writeFixtureJson} from './fixture_json.mjs';

const [argument,...extra]=process.argv.slice(2),rate=Number(argument);
assert.ok(!extra.length&&Number.isSafeInteger(rate)&&rate>=8000&&rate<=384000&&String(rate)===argument,
  'Select one original sample context rate from 8000 to 384000');
const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const original=await readFile(join(source,'public/js/audio.js'));
assert.equal(digest(original),provenance.inputs['public/js/audio.js'],'Accepted original audio module');
const text=original.toString().replace(/\r\n?/g,'\n'),body=text.replace(/^import .*$/gm,'').replace(/^export /gm,'');
const manifest=new Function(body+';return SFX_MANIFEST;')();
const contextPath='data/audio_sfx_rates/'+rate+'.json',contextBytes=await readFile(join(root,contextPath));
const parent=JSON.parse(contextBytes);
assert.equal(parent.scope,'original-sfx-synthesis-rate-only');
assert.equal(parent.sampleRate,rate);
assert.equal(parent.source.audioSha256,digest(text),'Same original sample and synthesis module');
const sourceInputs={'public/js/audio.js':digest(original)},files=[];
for(const [id,entry]of Object.entries(manifest))for(const [index,url]of (Array.isArray(entry)?entry:[entry]).entries()) {
  const path='public/'+url,target=await realpath(join(source,path)),within=relative(await realpath(join(source,'public/audio')),target);
  assert.ok(!isAbsolute(within)&&within!=='..'&&!within.startsWith('../')&&!within.startsWith('..\\'),'Local original audio asset');
  const bytes=await readFile(target);
  assert.equal(digest(bytes),provenance.inputs[path],'Accepted original sample bytes: '+path);
  sourceInputs[path]=digest(bytes);files.push({id,index,url,base64:bytes.toString('base64'),sha256:digest(bytes)});
}
const producers=['tools/capture_audio_sample_waveforms.mjs','tools/source_numeric_transfer.mjs','tools/fixture_json.mjs'];
const inputs=Object.fromEntries(await Promise.all(producers.map(async path=>
  [path,digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'))])));
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original sample waveforms require Chromium');
const browser=await chromium.launch({headless:true,executablePath:chromePath(),args:['--js-flags='+parent.source.jsFlags]});
try {
  assert.equal(browser.version(),parent.source.chromiumVersion,'Same original context renderer');
  const captured=await (await browser.newPage()).evaluate(async({body,files,rate,codec})=>{
    const encode=new Function('return ('+codec+');')();
    const f32=values=>{
      const bytes=new Uint8Array(values.buffer,values.byteOffset,values.byteLength),parts=[];
      for(let offset=0;offset<bytes.length;offset+=8192)parts.push(String.fromCharCode(...bytes.subarray(offset,offset+8192)));
      return btoa(parts.join(''));
    };
    const entries=new Map(files.map(file=>[file.url,file]));
    const buffers=async mode=>{
      const requests=[];
      const fetch=async url=>{
        requests.push(url);const file=entries.get(url);
        if(!file)throw new Error('Uncaptured original sample request: '+url);
        return {ok:mode!=='missing',arrayBuffer:async()=>mode==='decode'?new Uint8Array([1,2,3]).buffer:
          Uint8Array.from(atob(file.base64),value=>value.charCodeAt(0)).buffer};
      };
      const GameAudio=new Function('fetch',body+';return GameAudio;')(fetch);
      let bgmCalls=0;
      const audio=Object.assign(Object.create(GameAudio.prototype),{_ctx:new OfflineAudioContext(2,1,rate),
        _buffers:{},_sfxLoaded:false,lowPower:mode==='low',_loadBgm(){bgmCalls++;}});
      await audio._loadSamples();
      return {audio,GameAudio,summary:{mode,requests,bgmCalls,loaded:audio._sfxLoaded,
        counts:Object.fromEntries(Object.entries(audio._buffers).map(([id,values])=>[id,values.length]))}};
    };
    const loaded=await buffers('normal'),samples=[],probes=[],loader=[loaded.summary];
    for(const mode of ['missing','decode','low'])loader.push((await buffers(mode)).summary);
    for(const file of files) {
      const buffer=loaded.audio._buffers[file.id]?.[file.index];
      if(!buffer||![1,2].includes(buffer.numberOfChannels))throw new Error('Unsupported original decoded take: '+file.url);
      samples.push({...file,base64:undefined,sampleRate:buffer.sampleRate,frames:buffer.length,
        channels:Array.from({length:buffer.numberOfChannels},(_,index)=>f32(buffer.getChannelData(index)))});
      for(const randomValue of [0,.5,1-2**-32])for(const pan of [-.75,0,.75]) {
        const context=new OfflineAudioContext(2,Math.ceil(buffer.length/.9)+1024,rate);
        let sourceNode,reservation=NaN,draws=0;
        const native=context.createBufferSource.bind(context);
        context.createBufferSource=()=>{sourceNode=native();return sourceNode;};
        const audio=Object.assign(Object.create(loaded.GameAudio.prototype),{_ctx:context,_sfx:context.destination,
          _buffers:{[file.id]:[buffer]},_lastTake:new Map(),_count:value=>reservation=value});
        const originalRandom=Math.random;
        try {Math.random=()=>{draws++;return randomValue;};audio._playSample(file.id,.35,pan);}
        finally {Math.random=originalRandom;}
        if(draws!==1||sourceNode.buffer!==buffer)throw new Error('Unexpected original single-take selection');
        const rendered=await context.startRendering();
        probes.push({id:file.id,take:file.index,frames:rendered.length,
          controls:encode([.35,pan,randomValue,sourceNode.playbackRate.value,reservation]),
          channels:[f32(rendered.getChannelData(0)),f32(rendered.getChannelData(1))]});
      }
    }
    return {samples,probes,loader};
  },{body,files,rate,codec:encode.toString()});
  assert.equal(captured.samples.length,files.length,'Every original take decodes at the selected context rate');
  assert.equal(captured.probes.length,files.length*9,'Complete panning/rate corpus');
  for(const [path,hash]of Object.entries(sourceInputs))assert.equal(digest(await readFile(join(source,path))),hash,'Source changed during sample capture: '+path);
  assert.equal(digest(await readFile(join(root,contextPath))),digest(contextBytes),'Parent context changed during sample capture');
  for(const [path,hash]of Object.entries(inputs))assert.equal(digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n')),hash,'Producer changed during sample capture: '+path);
  await mkdir(join(root,'data/audio_sample_waveforms'),{recursive:true});
  await writeFixtureJson(join(root,'data/audio_sample_waveforms/'+rate+'.json'),{formatVersion:1,
    scope:'original-sample-context-waveforms',sampleRate:rate,source:{audioSha256:parent.source.audioSha256,sourceInputs,inputs,
      contextProfile:{path:contextPath,sha256:digest(contextBytes)},chromiumVersion:browser.version(),jsFlags:parent.source.jsFlags},...captured});
  console.log('AUDIO_SAMPLE_CAPTURE_PASS '+JSON.stringify({sampleRate:rate,samples:captured.samples.length,probes:captured.probes.length}));
} finally {await browser.close();}
