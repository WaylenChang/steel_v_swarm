export function minimapLaneReferences(grade,draw,d) {
  const begin=draw.indexOf('    this._mmLanes.forEach('),end=draw.indexOf('    ctx.setLineDash([]);',begin);
  const start=draw.lastIndexOf('    ctx.lineWidth = ',begin);
  if(begin<0||end<0||start<0)throw new Error('Missing original minimap lane pass');
  const render=new Function('laneCssColor','return function(){const ctx=this.mmCtx,w=250,h=220;'+draw.slice(start,end)+'};')(d.laneCssColor);
  const Client=new Function('return class {'+grade+'};')();
  const scalar=expression=>{const found=expression.exec(grade);if(!found)throw new Error('Missing original minimap lane classifier seam: '+expression);return Number(found[1]);};
  const rules={tunnelClearance:scalar(/y \+ ([\d.]+) < tn.ceil/),tunnelTolerance:scalar(/Math.abs\(y - tn.floor\) < ([\d.]+)/),
    bridgeExcess:scalar(/heightAt\(x, z\) \+ ([\d.]+)/),bridgeTolerance:scalar(/Math.abs\(y - d\) < ([\d.]+)/)};
  function strokes(lanes,ids) {
    const result=[];let points=[],dash=[];
    const ctx={lineWidth:0,globalAlpha:0,strokeStyle:'',setLineDash:value=>{dash=value;},beginPath:()=>{points=[];},
      moveTo:(x,z)=>{points.push([x,z]);},lineTo:(x,z)=>{points.push([x,z]);},
      stroke(){result.push({points,dash,colour:this.strokeStyle,width:this.lineWidth,alpha:this.globalAlpha});}};
    render.call({_mmLanes:lanes,cfg:{laneIds:ids},mmCtx:ctx,_world2mm:(x,z)=>[x,z]});
    return result;
  }
  const styles={},images=[];
  for(const name of ['ground','bridge','tunnel']) {
    const stroke=strokes([[{x:0,z:0,grade:name},{x:100,z:0,grade:name}]],[])[0];
    styles[name]={dash:stroke.dash,width:stroke.width,alpha:stroke.alpha,image:null};
    if(!stroke.dash.length)continue;
    // Encode the source's alternating intervals exactly on an integer texel grid.
    const decimals=Math.max(...[stroke.width,...stroke.dash].map(value=>(String(value).split('.')[1]||'').length));
    const scale=10**decimals,width=stroke.dash.reduce((sum,value)=>sum+value,0)*scale,height=stroke.width*scale;
    if(!Number.isInteger(width)||!Number.isInteger(height))throw new Error('Original dash cannot be represented by its decimal grid');
    const bytes=Buffer.alloc(width*height*4,255);
    for(let x=0;x<width;x++) {
      let offset=x,ink=true;
      for(const length of stroke.dash){if(offset<length*scale)break;offset-=length*scale;ink=!ink;}
      for(let y=0;y<height;y++)bytes[(y*width+x)*4+3]=ink?255:0;
    }
    styles[name].image=images.length;images.push({width,height,rgba:bytes.toString('base64')});
  }
  const cases=[{y:0},{y:0,tunnel:{floor:0,ceil:5,open:false}},{y:0,tunnel:{floor:0,ceil:5,open:true}},
    {y:0,tunnel:{floor:0,ceil:1.2,open:false}},{y:.6,tunnel:{floor:0,ceil:5,open:false}},
    {y:.59999,tunnel:{floor:0,ceil:5,open:false}},{y:10,deck:10,ground:9.5},
    {y:10,deck:10,ground:9.49},{y:10.6,deck:10},{y:10.60001,deck:10},
    {y:0,deck:0,tunnel:{floor:0,ceil:5,open:false}}].map((row,index)=>({ground:0,deck:null,tunnel:null,...row,x:index,z:index%3}));
  const samples=cases.map(({x,z,y})=>({x,z,y}));
  const lanes=[null,{samples:[]},{samples:[samples[0]]},{samples},{samples:[...samples].reverse()}];
  const terrain={heightAt:x=>cases[x].ground,deckY:x=>cases[x].deck,tunnelAt:x=>cases[x].tunnel};
  const client=new Client();Object.assign(client,{terrain,_laneSurf:lanes});
  const classified=client._gradeLanes();
  const ids=[null,null,null,-1,7];
  return {rules:{...rules,styles,images},fixtures:{minimapLanes:[{cases,lanes,ids,classified,strokes:strokes(classified,ids)}]}};
}
