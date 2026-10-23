import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function localStatusReferences(source) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const [game,sim]=await Promise.all(['public/js/game.js','server/sim.js'].map(async file=>(await readFile(join(source,file),'utf8')).replace(/\r\n?/g,'\n')));
  const lines=sim.split('\n');
  const emp=lines.find(line=>line.includes('o.emp = Math.round((e.empUntil - this.t) * 10) / 10'));
  const castAt=lines.findIndex(line=>line.includes('if (e.cast && (e.cast.start + e.cast.dur > this.t)) o.cst ='));
  const empAssign=/this\.empLeft = e\.emp \|\| 0;/.exec(game)?.[0];
  const castAssign=/this\.castLeft = e\.cst \|\| 0;/.exec(game)?.[0];
  const startUntil=/this\._castingUntil = performance\.now\(\) \/ 1000 \+ \(ev.dur \|\| [\d.]+\);/.exec(game)?.[0];
  const startLeft=/this\.castLeft = ev\.dur \|\| [\d.]+;/.exec(game)?.[0];
  const cancel=/this\._castingUntil = 0;\s*this\.castLeft = 0;/.exec(game)?.[0];
  if(!emp||castAt<0||!lines[castAt+1].includes('e.castLockUntil')||!empAssign||!castAssign||!startUntil||!startLeft||!cancel)
    throw new Error('Missing original private status publication/client synchronization seam');
  const publish=new Function('e','const o={};'+emp+'\n'+lines.slice(castAt,castAt+2).join('\n')+'\nreturn o;');
  const apply=new Function('e',castAssign+'\n'+empAssign);
  const start=new Function('performance','ev',startUntil+'\n'+startLeft);
  const finish=new Function(cancel);
  const casting=new Function(`return function ${grabMethod(game,'_isCasting').trimStart().slice('_isCasting'.length)}`)();
  const context={empLeft:0,castLeft:0,_castingUntil:0};
  const commands=[
    {kind:'snapshot',now:10,emp:10.049999,cast:10.4,lock:12},
    {kind:'advance',now:10.5},
    {kind:'snapshot',now:10.6,emp:10.65,lock:10.9},
    {kind:'advance',now:11.1},
    {kind:'snapshot',now:11.2,emp:0},
    {kind:'start',now:12,duration:0},
    {kind:'advance',now:13},
    {kind:'snapshot',now:13.1,emp:13.11},
    {kind:'start',now:14,duration:2},
    {kind:'cancel',now:14.1},
    {kind:'advance',now:14.2},
  ];
  return commands.map(command=>{
    let publication=null;
    if(command.kind==='snapshot') {
      publication=publish.call({t:command.now},{empUntil:command.emp??0,castLockUntil:command.lock??0,
        cast:command.cast?{start:0,dur:command.cast}:null});
      apply.call(context,publication);
    } else if(command.kind==='start') start.call(context,{now:()=>command.now*1000},{dur:command.duration});
    else if(command.kind==='cancel') finish.call(context);
    return {...command,publication,result:{emp:context.empLeft,cast:context.castLeft,until:context._castingUntil,casting:casting.call(context,command.now)}};
  });
}
