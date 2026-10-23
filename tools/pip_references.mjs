import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function pipReferences(source,d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const text=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
  const declaration=/const PIP = (\{[^\n]+\});/.exec(text);
  const camera=/this\.pipCam = new THREE\.PerspectiveCamera\(PIP.FOV, 1 \/ PIP.ASPECT, ([\d.]+), span \* ([\d.]+)\)/.exec(text);
  const sources=grabMethod(text,'_pipSources'),render=grabMethod(text,'_renderPips');
  const counts=/\? (\d+) : (\d+);/.exec(sources);
  const heights=/position.y \+= p.ent.decoy \? ([\d.]+) : ([\d.]+);/.exec(render);
  const border=/setScissor\(x - (\d+), y - \1, pw \+ (\d+), ph \+ \2\)/.exec(render);
  if(!declaration||!camera||!counts||!heights||!border||Number(border[2])!==2*Number(border[1]))throw new Error('Missing original PiP camera/render seams');
  const rules={...new Function('return ('+declaration[1]+');')(),NEAR:Number(camera[1]),FAR_FACTOR:Number(camera[2]),
    LOW_COUNT:Number(counts[1]),HIGH_COUNT:Number(counts[2]),DECOY_EYE:Number(heights[1]),HERO_EYE:Number(heights[2]),BORDER:Number(border[1])};
  let low=false;
  const Pip=new Function('PIP','THREE','lowPower','sideInfo','return class {\n'+sources+'\n'+render+'\n};')(rules,THREE,()=>low,d.sideInfo);
  const definition=[
    {id:1,pid:17,hero:true,isSelf:true,si:0},
    {id:2,pid:17,hero:true,si:2},
    {id:3,pid:18,hero:true,si:0},
    {id:4,pid:17,hero:true,si:1},
    {id:5,pid:17,hero:true,si:0},
    {id:6,pid:17,hero:true,si:0,dead:true},
    {id:7,pid:17,decoy:true,si:0},
    {id:8,pid:17,decoy:true,si:0,lost:true},
    {id:9,pid:17,decoy:true,si:0,dead:true},
    {id:10,pid:18,decoy:true,si:0},
    {id:11,pid:17,si:0},
  ];
  const fixtures=[];
  for(const drone of [false,true])for(const dead of [false,true])for(const side of ['', 'STEEL','SWARM','SUPER'])
  for(const power of [false,true])for(const scale of [0,.5,1,1.5]) {
    low=power;
    const context=new Pip();
    Object.assign(context,{side,dead,isDrone:drone,youId:17,_resScale:scale,
      ents:new Map(definition.map(row=>[row.id,{dead:false,isSelf:false,hero:false,decoy:false,lost:false,...row}]))});
    const rows=[...context.ents.values()].map(row=>({id:row.id,peer:row.pid,hero:row.hero,self:row.isSelf,dead:row.dead,decoy:row.decoy,lost:row.lost,index:row.si}));
    fixtures.push({drone,dead,side,low:power,scale,rows,ids:context._pipSources().map(row=>row.ent.id)});
  }
  const frames=[];
  for(const drone of [false,true])for(const size of [[320,568],[1440,900],[3840,2160]])for(const power of [false,true]) {
    low=power;
    const context=new Pip(),draws=[],calls=[];
    let viewport=[],scissor=true;
    const entities=new Map(definition.map((row,index)=>[row.id,{dead:false,isSelf:false,hero:false,decoy:false,lost:false,...row,
      ry:(index-4)*.31,mesh:{position:new THREE.Vector3(index*7,13+index,-index*11),visible:index!==3}}]));
    const renderer={getClearColor:target=>target.setHex(0x123456),getClearAlpha:()=>.4,
      setClearColor:(color,alpha)=>calls.push(['color',new THREE.Color(color).getHex(),alpha]),
      setScissorTest:value=>{scissor=value;},setScissor:()=>{},clear:()=>{},setViewport:(...value)=>{viewport=value;},
      render:(_scene,camera)=>{draws.push({rect:[viewport[0],size[1]-viewport[1]-viewport[3],viewport[2],viewport[3]],
        position:camera.position.toArray(),yaw:camera.rotation.y,fov:camera.fov,aspect:camera.aspect,
        hidden:[...entities.values()].filter(row=>!row.mesh.visible).map(row=>row.id),cockpit:context.cockpit.visible});}};
    Object.assign(context,{side:'STEEL',dead:false,isDrone:drone,youId:17,_resScale:1,ents:entities,
      renderer,scene:{},canvas:{clientWidth:size[0],clientHeight:size[1]},cockpit:{visible:true},
      pipCam:new THREE.PerspectiveCamera(rules.FOV,1/rules.ASPECT,rules.NEAR,4000)});
    const selected=context._pipSources().map(row=>({id:row.ent.id,position:row.ent.mesh.position.toArray(),yaw:row.ent.ry,decoy:row.ent.decoy}));
    context._renderPips();
    frames.push({drone,size,low:power,selected,draws,restored:context.cockpit.visible&&!scissor&&viewport.join(',')===[0,0,...size].join(','),
      visibility:[...entities.values()].map(row=>({id:row.id,visible:row.mesh.visible}))});
  }
  return {rules,fixtures:{pipSources:fixtures,pipFrames:frames},inputs:['public/js/game.js','public/js/data.js','out/forest_review/three.module.js']};
}
