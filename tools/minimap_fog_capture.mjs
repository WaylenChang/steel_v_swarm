export async function captureMinimapFog(page,methods,canvasSize) {
  return page.evaluate(({methods,canvasSize})=>{
    const draw=methods[0],lane=draw.indexOf('    this._mmLanes.forEach('),end=draw.lastIndexOf('    ctx.lineWidth = ',lane);
    if(lane<0||end<0)throw new Error('Missing original minimap fog rendering boundary');
    const Client=new Function('return class {'+draw.slice(0,end)+'\n}\n'+methods.slice(1).join('\n')+'};')();
    const [width,height]=canvasSize;
    const canvas=()=>{const value=document.createElement('canvas');value.width=width;value.height=height;return value;};
    const terrain={minX:0,maxX:1000,minZ:0,maxZ:600},background=[128,154,111,255];
    const base=canvas(),baseCtx=base.getContext('2d');baseCtx.fillStyle='rgb('+background.slice(0,3).join(',')+')';baseCtx.fillRect(0,0,width,height);
    let reveals=[];
    function create() {
      const client=new Client();Object.assign(client,{terrain,mmCtx:canvas().getContext('2d'),minimapCanvas:{width,height},
        _mmSeen:canvas(),_mmFog:canvas(),_mmScr:canvas(),_mmBase:base,_mmLast:0,_mmWarmUntil:0,_pulseUntil:0});
      const ctx=client._mmScr.getContext('2d'),ellipse=ctx.ellipse,gradient=ctx.createRadialGradient,
        move=ctx.moveTo,line=ctx.lineTo,fill=ctx.fill;
      let points=[],hard=0,soft=0;
      ctx.ellipse=function(x,y,rx,ry,...rest){reveals.push({source:hard++,soft:false,center:[x,y],radius:[rx,ry],polygons:[]});return ellipse.call(this,x,y,rx,ry,...rest);};
      ctx.createRadialGradient=function(x,y,r0,x1,y1,r1){const matrix=this.getTransform();reveals.push({source:soft++,soft:true,
        center:[matrix.e,matrix.f],radius:[r1*matrix.a,r1*matrix.d],polygons:[]});return gradient.call(this,x,y,r0,x1,y1,r1);};
      ctx.moveTo=function(x,y){points=[[x,y]];return move.call(this,x,y);};
      ctx.lineTo=function(x,y){points.push([x,y]);return line.call(this,x,y);};
      ctx.fill=function(...args){if(this.globalCompositeOperation==='destination-out')reveals.at(-1).polygons.push(points);return fill.apply(this,args);};
      client.resetCounters=()=>{hard=0;soft=0;};
      return client;
    }
    const full={x0:0,z0:0,x1:1000,z1:600},near={x0:50,z0:80,x1:550,z1:430};
    const wall=[{x:310,z:200,r:25}];
    const definitions=[
      {now:10,sources:[],blockers:[],window:full},
      {now:11,sources:[[230,200,180]],blockers:wall,window:full},
      {now:12,sources:[[230,200,180],[420,200,160]],blockers:wall,window:full},
      {now:13,sources:[[230,200,180]],blockers:wall,window:near},
      {now:14,sources:[[750,420,120]],blockers:[],window:full},
      {now:15,side:'',sources:[],blockers:[],window:near},
      {now:16,pulseUntil:18,sources:[],blockers:[],window:near},
      {now:20,sources:[[-50,100,100],[1000,600,1]],blockers:[],window:full},
      {now:21,sources:[],blockers:[],window:full},
      {now:22,reset:true,sources:[],blockers:[],window:full},
    ];
    let client=create();const frames=[];
    const png=value=>({width,height,png:value.toDataURL('image/png').split(',')[1]});
    const probes=(frame,project)=>{
      const points=[[3,3],[width-4,3],[3,height-4],[width-4,height-4],[Math.floor(width/2),Math.floor(height/2)]];
      for(const [x,z]of frame.sources){const [px,py]=project(x,z);if(px>=0&&py>=0&&px<width&&py<height)points.push([Math.floor(px),Math.floor(py)]);}
      return points;
    };
    for(const definition of definitions) {
      if(definition.reset)client=create();
      const frame={side:'STEEL',...definition};
      client.side=frame.side;client._mmWindow=()=>frame.window;client._mmVision=()=>frame.sources;
      client.terrain.blockers=frame.blockers;client._blockGrid=client._buildBlockGrid(frame.blockers);
      if(frame.pulseUntil!=null)client._pulseUntil=frame.pulseUntil;
      reveals=[];client.resetCounters();client._drawMinimap(frame.now);
      frames.push({...frame,pulseUntil:client._pulseUntil,reveals,image:png(client.mmCtx.canvas),seen:png(client._mmSeen),fog:png(client._mmFog),
        probes:probes(frame,(x,z)=>client._world2mm(x,z,width,height)),seenProbes:probes(frame,(x,z)=>client._world2mmFull(x,z,width,height))});
    }
    return {size:canvasSize,terrain:{minX:terrain.minX,maxX:terrain.maxX,minZ:terrain.minZ,maxZ:terrain.maxZ},background,frames};
  },{methods,canvasSize});
}
