import {readFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function statusIconReferences(source) {
  const [game,main]=await Promise.all(['game.js','main.js'].map(async name=>(await readFile(join(source,'public/js',name),'utf8')).replace(/\r\n?/g,'\n')));
  const begin=game.indexOf('    if (!sh) {\n      const icons = [];');
  const end=game.indexOf('\n    } else {\n      this.hud.statusIcons?.([]);',begin);
  const defsBegin=main.indexOf('const DEFS = {',main.indexOf('statusIcons: (() => {'));
  const defsEnd=main.indexOf('\n      const el =',defsBegin);
  if(begin<0||end<0||defsBegin<0||defsEnd<0) throw new Error('Missing original status icon composition/render seams');
  const block=game.slice(begin+'    if (!sh) {'.length,end);
  const definitions=new Function(main.slice(defsBegin,defsEnd)+'\nreturn DEFS;')();
  for(const definition of Object.values(definitions)) {
    definition.texts=[];
    definition.svg=definition.svg.replace(/<text\b([^>]*)>([^<]*)<\/text>/g,(_,attributes,text)=>{
      const attr=Object.fromEntries([...attributes.matchAll(/([\w-]+)="([^"]*)"/g)].map(match=>[match[1],match[2]]));
      if(attr['text-anchor']!=='middle') throw new Error('Unimplemented original status SVG text alignment');
      definition.texts.push({text,x:Number(attr.x),y:Number(attr.y),size:Number(attr['font-size']),weight:Number(attr['font-weight']),color:attr.fill,families:attr['font-family'].split(',').map(value=>value.trim())});
      return '';
    });
  }
  let now=10;
  const observe=new Function('performance',`return function(){${block}}`)({now:()=>now*1000});
  const labels={};
  // Execute every branch to recover labels, including conditional IDs.
  const capture=input=>{
    const context={...input,hud:{statusIcons:icons=>{for(const item of icons) labels[item.id]=item.label;}}};
    observe.call(context);
  };
  capture({freezeLeft:1,stunLeft:3,empLeft:2,slowLeft:1,slowF:.4,bleedLeft:3,blindLeft:1,confLeft:1,markLeft:1,unbalLeft:1,hiSupLeft:1,stealthLeft:1,invLeft:1,selfMods:[['speed',2,1]],_buffsLeft:['tempered','hardened','vampiric','bounty'].map(id=>[id,1])});
  capture({stunLeft:2,empLeft:3,slowLeft:1,slowF:.5,bleedLeft:3});
  capture({slowLeft:1,slowF:.7,bleedLeft:3,_burnAt:9});
  capture({slowLeft:1,slowF:.7,bleedLeft:3});
  for(const id of Object.keys(definitions)) if(!labels[id]) throw new Error('Missing original status icon label: '+id);
  const context={hud:{statusIcons:icons=>{context.output=structuredClone(icons);}}};
  const fields=['freezeLeft','stunLeft','empLeft','slowLeft','bleedLeft','blindLeft','confLeft','markLeft','unbalLeft','hiSupLeft','stealthLeft','invLeft'];
  const frames=[{}, {freezeLeft:2,slowLeft:4,slowF:.4}, {freezeLeft:1,slowLeft:3,slowF:.4},
    {freezeLeft:5,slowLeft:1,slowF:.4}, {}, {freezeLeft:1},
    ...[.1,.1000001,.0999999].flatMap(gap=>[{stunLeft:2+gap,empLeft:2},{stunLeft:2,empLeft:2+gap}]),
    ...[0,.4,.5,.500001,.7].flatMap(slowF=>[{slowLeft:2,bleedLeft:3,slowF},{slowLeft:3,bleedLeft:2,slowF}]),
    {bleedLeft:4,burnNow:true}, {bleedLeft:3,elapsed:2.499}, {bleedLeft:2,elapsed:.001},
    {blindLeft:1,confLeft:1,markLeft:1,unbalLeft:1,hiSupLeft:1,stealthLeft:1,invLeft:1,
      selfMods:[['speed',1.5,0],['jump',2,2],['armor',2,3]],_buffsLeft:[['bounty',2],['hardened',3],['unknown',1]]},
    {spectating:true}, {selfMods:[['jump',2,1]],_buffsLeft:[['bounty',1]]}, {}];
  const fixtures=[];
  for(const frame of frames) {
    now+=frame.elapsed||.1;
    if(frame.burnNow) context._burnAt=now;
    const values={...Object.fromEntries(fields.map(key=>[key,0])),slowF:.6,selfMods:[],_buffsLeft:[],...frame};
    Object.assign(context,values);
    if(frame.spectating) context.hud.statusIcons([]); else observe.call(context);
    fixtures.push({now,values,spectating:!!frame.spectating,burnAt:context._burnAt||0,result:context.output,maximum:{...context._statusMax}});
  }
  const burn=/now\(\) \/ 1000 - this\._burnAt < ([\d.]+)/.exec(block);
  if(!burn) throw new Error('Missing original burn-icon event window');
  const buildBegin=main.indexOf('      function buildIcon(item) {',defsEnd);
  const buildEnd=main.indexOf('\n      return (list) => {',buildBegin);
  if(buildBegin<0||buildEnd<0) throw new Error('Missing original status icon clock renderer');
  const cache=new Map();
  const build=new Function('DEFS','durCache',main.slice(buildBegin,buildEnd)+'\nreturn buildIcon;')(definitions,cache);
  const rendered=[];
  for(const remS of [.01,.05,.15,.95,1.05,2.55,9.95,9.999,10,10.5,29.9]) for(const maxS of [0,remS,remS*2,remS*100]) {
    const item={id:'freeze',remS,maxS,positive:false,label:labels.freeze};
    const html=build(item);
    const tip=/<circle cx="([\d.-]+)" cy="([\d.-]+)" r="1.4"/.exec(html);
    rendered.push({item,result:{timer:/class="si-t">([^<]+)/.exec(html)[1],
      degrees:Number(/0.52\) ([\d.]+)deg/.exec(html)[1]),
      dashOffset:Number(/stroke-dashoffset="([\d.]+)"/.exec(html)[1]),showTip:!!tip,
      ...(tip?{tipX:Number(tip[1]),tipY:Number(tip[2])}:{})}});
  }
  return {rules:{labels,definitions,burnWindow:Number(burn[1])},fixtures,rendered};
}
