import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function geometryLodReferences(source,d) {
  const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
  const [lod,game]=await Promise.all(['public/js/lod.js','public/js/game.js'].map(async path=>(await readFile(join(source,path),'utf8')).replace(/\r\n?/g,'\n')));
  const api=new Function(lod.replace(/^export /gm,'')+'\nreturn {GEO,lodDue,geoFarM,geoKeep,geoTrimKeep,geoOutlineKeep,applyGeoLod};')();
  const method=grabMethod(game,'_tickGeoLod');
  const defaultHeight=Number(/const h = ent.dimH \|\| ([\d.]+);/.exec(method)?.[1]);
  if(!Number.isFinite(defaultHeight)) throw new Error('Missing original geometry LOD height fallback');
  const scope={...api,UNITS:d.UNITS,dofAimBlend:d.dofAimBlend};
  const tick=new Function(...Object.keys(scope),`return function ${method.trimStart().slice('_tickGeoLod'.length)}`)(...Object.values(scope));
  const definitions=[{parent:-1,flags:{},visible:true},{parent:0,flags:{isOutline:true},visible:true},
    {parent:0,flags:{geoDetail:true},visible:true},{parent:0,flags:{geoDetail:true,geoKeep:true},visible:false},
    {parent:0,flags:{},visible:false},{parent:0,flags:{geoKeep:true},visible:true},
    {parent:5,flags:{isOutline:true},visible:true}];
  const base=d.UNITS.robot.fov,zoom=d.UNITS.robot.zoomFov??base;
  const programs=[];
  for(const id of ['13','42','unit:🦾']) {
    const nodes=definitions.map(spec=>({userData:{...spec.flags},visible:spec.visible}));
    const mesh=nodes[0];mesh.position={x:0,y:0,z:0};mesh.traverse=callback=>nodes.forEach(callback);
    const entity={id,dimH:defaultHeight,mesh},context={camera:{position:{x:0,y:defaultHeight*.5,z:0},fov:base},
      baseFov:base,heroKind:'robot',side:'STEEL',dead:false,ents:new Map([[id,entity]])};
    const scenarios=[{distance:api.GEO.OUTLINE_M*1.1},{distance:api.GEO.TRIM_M*.5},
      {distance:(api.GEO.TRIM_M+api.GEO.OUTLINE_M)*.5},
      {distance:api.GEO.TRIM_M*(1+api.GEO.HYST)*.5},
      {distance:api.GEO.TRIM_M*api.GEO.HYST-.01},
      {distance:api.GEO.OUTLINE_M*1.1},{distance:api.GEO.OUTLINE_M*(1+api.GEO.HYST)*.5},
      {distance:api.GEO.OUTLINE_M*api.GEO.HYST-.01},
      {distance:api.GEO.OUTLINE_M*1.1,fov:zoom},
      {distance:api.GEO.OUTLINE_M*1.1,fov:zoom,viewerDead:true},
      {distance:0,self:true},{distance:0,dead:true},{distance:0,garrison:true},{distance:0,visible:false},
      {distance:0},{distance:api.GEO.TRIM_M,height:20},{distance:api.GEO.TRIM_M,height:0}];
    const commands=scenarios.flatMap(scenario=>Array.from({length:api.GEO.STRIDE+1},()=>scenario));
    commands.push(...[0x7fffffff,0x80000000,0xffffffff,-1,0].map(frame=>({frame,distance:api.GEO.TRIM_M*.5})));
    const steps=[];
    for(const [index,command] of commands.entries()) {
      const input={frame:command.frame??index,point:[command.distance,0,0],height:command.height??defaultHeight,
        self:!!command.self,dead:!!command.dead,garrison:!!command.garrison,visible:command.visible!==false,
        fov:command.fov??base,base,zoom,viewerDead:!!command.viewerDead};
      context._lodFrame=input.frame;context.dead=input.viewerDead;context.camera.fov=input.fov;
      entity.isSelf=input.self;entity.dead=input.dead;entity.gar=input.garrison;entity.dimH=input.height;
      Object.assign(mesh.position,{x:input.point[0],y:input.point[1],z:input.point[2]});mesh.visible=input.visible;
      tick.call(context);
      const height=input.height||defaultHeight;
      const dy=input.point[1]+height*.5-context.camera.position.y;
      steps.push({...input,d2:input.point[0]**2+dy**2,
        blend:input.viewerDead?0:d.dofAimBlend(input.fov,base,zoom),
        trim:entity._geoTrim??null,outline:entity._geoOut??null,visibility:nodes.map(node=>node.visible)});
    }
    programs.push({id,nodes:definitions,camera:[0,defaultHeight*.5,0],steps});
  }
  return {rules:{...api.GEO,defaultHeight},fixtures:{geometryLodPrograms:programs}};
}
