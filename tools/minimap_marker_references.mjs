export function minimapColour(value) {
  const rgba=/^rgba?\(([^)]+)\)$/.exec(value);
  if(rgba){const parts=rgba[1].split(',').map(Number);return [...parts.slice(0,3).map(value=>value/255),parts[3]??1];}
  let hex=value.replace('#','');if(hex.length===3)hex=[...hex].map(value=>value+value).join('');
  if(!/^[a-f\d]{6}$/i.test(hex))throw new Error('Unsupported original minimap colour: '+value);
  return [0,2,4].map(index=>parseInt(hex.slice(index,index+2),16)/255).concat(1);
}

export function minimapMarkerReferences(text,draw,d) {
  const start=draw.indexOf('    for (const ent of this.ents.values()) {');
  const end=draw.indexOf('    const label = ',start);
  const memoryLine=text.split('\n').find(line=>line.includes('this._seenBunkers.set('));
  const initialWidth=/ctx.lineWidth = ([\d.]+);/.exec(draw);
  if(start<0||end<0||!memoryLine||!initialWidth)throw new Error('Missing original minimap marker/memory seams');
  const render=new Function('sideInfo','return function(){const ctx=this.mmCtx,w=250,h=220;'+draw.slice(start,end)+'};')(d.sideInfo);
  const remember=new Function('e',memoryLine);
  function capture(rows,viewer,bunkers=[],own=null,yaw=0,inherit=false) {
    const commands=[];let path=null,position=[0,0],rotation=0,stack=[];
    const context={fillStyle:'#000000',strokeStyle:'#000000',lineWidth:inherit?null:Number(initialWidth[1]),
      save(){stack.push({position:[...position],rotation,fillStyle:this.fillStyle,strokeStyle:this.strokeStyle,lineWidth:this.lineWidth});},
      restore(){const saved=stack.pop();position=saved.position;rotation=saved.rotation;Object.assign(this,saved);},
      translate(x,y){position=[x,y];},rotate(value){rotation=value;},
      beginPath(){path=null;},closePath(){},
      moveTo(x,y){path={shape:'polygon',points:[[x,y]]};},lineTo(x,y){path.points.push([x,y]);},
      arc(x,y,r){path={shape:'circle',center:[x,y],radius:r};},
      emit(shape,fill){commands.push({...shape,fill,colour:minimapColour(fill?this.fillStyle:this.strokeStyle),
        width:fill?null:this.lineWidth,position:[...position],rotation});},
      fill(){this.emit(path,true);},stroke(){this.emit(path,false);},
      fillRect(x,y,w,h){this.emit({shape:'rect',rect:[x,y,w,h]},true);},
      strokeRect(x,y,w,h){this.emit({shape:'rect',rect:[x,y,w,h]},false);}};
    render.call({mmCtx:context,side:viewer,pos:{x:own?.[0]??0,z:own?.[1]??0},viewMode:'fpv',yaw,bodyYaw:yaw,
      ents:new Map(rows.map((row,index)=>[index,{...row,mesh:{position:{x:row.point[0],z:row.point[1]}}}])),
      _world2mm:(x,z)=>[x,z],_seenBunkers:new Map(bunkers.map((row,index)=>[index,row])),samMeshes:new Map()});
    // The original own-arrow branch depends on allegiance. Templates for other
    // markers suppress that branch without changing their enemy/ally predicate.
    return own===null&&viewer?commands.slice(0,-1):commands;
  }
  const sides=[...new Set(['',...Object.keys(d.SIDES),...Object.keys(d.THIRD.SIDES),d.SUPER_SIDE])];
  const templates={};
  for(const viewer of sides) {
    templates[viewer]={};
    for(const side of sides) {
      const family={};
      for(const key of ['base','tower','hero','self','npc','heli','bunker']) {
        const row={kind:key==='hero'||key==='self'?'robot':key==='npc'?'soldier':key,side,
          hero:key==='hero'||key==='self',isSelf:key==='self',neutral:false,point:[0,0]};
        family[key]=capture(key==='bunker'?[]:[row],viewer,key==='bunker'?[{x:0,z:0,side}]:[],null,0,true);
      }
      templates[viewer][side]=family;
    }
  }
  const own=capture([],'STEEL',[],[0,0]);
  const programs=[];
  const baseRows=[{kind:'base',side:'SWARM',point:[50,60]},{kind:'robot',side:'STEEL',hero:true,point:[70,80]},
    {kind:'tower',side:'SWARM',point:[90,100]},{kind:'heli',side:'SWARM',point:[110,120]},
    {kind:'base',side:'STEEL',point:[130,140]},{kind:'soldier',side:'GUER',point:[150,160]},
    {kind:'car',side:'',neutral:true,point:[170,180]},{kind:'robot',side:'STEEL',hero:true,isSelf:true,point:[190,200]},
    {kind:'bunker',side:'MILI',point:[210,220]},{kind:'soldier',side:'SWARM',hp:0,point:[230,240]}];
  for(const viewer of sides)for(const reverse of [false,true])for(const yaw of [0,.73,-2.1]) {
    const rows=baseRows.map(row=>({hero:false,isSelf:false,neutral:false,...row}));if(reverse)rows.reverse();
    const bunkers=[{x:45,z:85,side:'MILI'},{x:25,z:125,side:'GUER'}],point=viewer?[95,145]:null;
    programs.push({rows,viewer,bunkers,own:point,yaw,commands:capture(rows,viewer,bunkers,point,yaw)});
  }
  const trace=[[{k:'bunker',x:-.5,z:.5,s:'GUER'}],[],[{k:'bunker',x:-.4,z:.4,s:'MILI'}],
    [{k:'soldier',x:20,z:-30,s:'STEEL'},{k:'bunker',x:20.5,z:-30.5,s:'GUER'}],[]];
  const client={_seenBunkers:new Map()},memory=[];
  for(const rows of trace) {
    for(const row of rows)remember.call(client,row);
    memory.push({rows,entries:[...client._seenBunkers].map(([key,row])=>({key,...row}))});
  }
  return {rules:{templates,own,initialWidth:Number(initialWidth[1])},fixtures:{minimapMarkers:programs,minimapMemory:memory}};
}
