import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function controlEffectReferences(source, d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const [game,main,css]=await Promise.all(['public/js/game.js','public/js/main.js','public/css/style.css'].map(async file=>(await readFile(join(source,file),'utf8')).replace(/\r\n?/g,'\n')));
  const scope={...d};
  const method=name=>new Function(...Object.keys(scope),`return function ${grabMethod(game,name).trimStart().slice(name.length)}`)(...Object.values(scope));
  const feed=method('_ccFeed'),trigger=method('_blindFlash'),advance=method('_updateCcFlash'),clear=method('_clearCcFlash');
  const feedSource=grabMethod(game,'_ccFeed');
  const fields=[...feedSource.matchAll(/edge\('([^']+)',\s*this\.([A-Za-z0-9_]+),/g)].map(match=>({id:match[1],field:match[2]}));
  const unbalanced=/edge\('([^']+)',\s*this\._unbalanced\(\) \? 1 : 0,/.exec(feedSource);
  if(fields.length!==9||!unbalanced) throw new Error('Missing original control edge roster');
  fields.push({id:unbalanced[1],field:'unbalanced'});
  const values=input=>Object.assign(Object.fromEntries(fields.map(edge=>[edge.field,0])),input);
  const make=()=>({_ccFlashLeft:0,_ccFlashPeak:0,_unbalanced(){return !!this.unbalanced;}});
  const edges=[];
  for(const edge of fields) {
    const context=Object.assign(make(),values({[edge.field]:1})),notices=[],peaks=[];
    context.hud={feed:text=>notices.push(text)};context._blindFlash=value=>peaks.push(value);
    feed.call(context);
    if(notices.length!==1||peaks.length>1) throw new Error('Original control edge was not isolated');
    edges.push({...edge,text:notices[0],peak:peaks[0]??null});
  }
  const style=/\.cc-flash\s*\{([^}]+)\}/.exec(css)?.[1];
  const layer=Number(/z-index:\s*(\d+)/.exec(style||'')?.[1]);
  const color=/background:\s*(#[0-9a-f]+)/i.exec(style||'')?.[1];
  const renderer=/ccFlash: \(a\) => \{([\s\S]*?)\n    },/.exec(main)?.[1];
  if(!Number.isFinite(layer)||!color||!renderer) throw new Error('Missing original control flash DOM/CSS presentation');
  const element={style:{opacity:'0'}};
  const paint=new Function('$','a',renderer);
  const context=make(),steps=[];
  context._blindFlash=trigger;
  const commands=[
    {kind:'observe',values:{stunLeft:1}},{kind:'advance',delta:.1},
    {kind:'observe',values:{stunLeft:1,confLeft:1}},{kind:'advance',delta:.35},
    {kind:'observe',values:{stunLeft:1,confLeft:1,empLeft:1,blindLeft:1}},
    {kind:'advance',delta:.6},{kind:'observe',values:{}},{kind:'observe',values:{blindLeft:1}},
    {kind:'trigger',peak:.3},{kind:'advance',delta:2},{kind:'advance',delta:.1},
    {kind:'clear'},{kind:'observe',values:{blindLeft:1}},{kind:'advance',delta:.01},
    {kind:'observe',values:{unbalanced:1}},{kind:'advance',delta:2},{kind:'clear'},
  ];
  for(const command of commands) {
    const notices=[],opacity=[],painted=[];
    context.hud={feed:text=>notices.push(text),ccFlash:alpha=>{
      opacity.push(alpha);paint(()=>element,alpha);painted.push(Number(element.style.opacity));
    }};
    const input=command.kind==='observe'?values(command.values):null;
    if(input){Object.assign(context,input);feed.call(context);}
    else if(command.kind==='trigger') trigger.call(context,command.peak);
    else if(command.kind==='advance') advance.call(context,command.delta);
    else clear.call(context);
    const flags=Object.fromEntries(edges.filter(edge=>edge.id in context).map(edge=>[edge.id,context[edge.id]]));
    steps.push({...command,...(input?{values:input}:{}),notices,opacity,painted,
      result:{left:context._ccFlashLeft,peak:context._ccFlashPeak,flags,alpha:d.ccFlashAlpha(context._ccFlashLeft,context._ccFlashPeak)}});
  }
  const curves=[];
  for(const left of [-1,0,.1,.3,.6,1.19,1.2,1.5,2]) for(const peak of [-1,0,.55,.85,.96,1,2])
    curves.push({left,peak,result:d.ccFlashAlpha(left,peak)});
  return {rules:{edges,flash:d.CC_FLASH,duration:d.ccFlashDur(),layer,color},steps,curves};
}
