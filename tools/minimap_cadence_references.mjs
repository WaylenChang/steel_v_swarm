import {minimapColour} from './minimap_marker_references.mjs';

export function minimapCadenceReferences(init,draw) {
  const warm=/_mmWarmUntil = performance.now\(\) \/ 1000 \+ ([\d.]+)/.exec(init);
  const gate=/const mmGate = now <[^\n]+\? ([\d.]+) : ([\d.]+);/.exec(draw);
  const start=draw.indexOf('    const mmGate = '),end=draw.indexOf('    this._mmLast = now;',start);
  const labelStart=draw.indexOf('    const label = ');
  if(!warm||!gate||start<0||end<0||labelStart<0)throw new Error('Missing original minimap cadence/legend seams');
  const advance=new Function('now',draw.slice(start,end)+'this._mmLast = now;return true;');
  const cadence=[];
  for(const configuredAt of [0,19.75]) {
    const client={_mmWarmUntil:configuredAt+Number(warm[1]),_mmLast:0},frames=[];
    for(const [offset,invalidate] of [[0,false],[.2,false],[.99999,false],[1,false],[1.2,false],[2,false],[2.99999,false],
      [3,false],[3.19999,false],[3.2,false],[4,false],[20,false],[20,false],[20.05,false],[20.05,true],[20.1,false]]) {
      if(invalidate)client._mmLast=0;
      const now=configuredAt+offset,due=!!advance.call(client,now);
      frames.push({now,invalidate,due,last:client._mmLast});
    }
    cadence.push({configuredAt,warmUntil:client._mmWarmUntil,frames});
  }
  const legend=new Function('ctx','w','h','v',draw.slice(labelStart,draw.lastIndexOf('}')));
  function label(mode,width) {
    const ctx={fillStyle:'',font:'',textAlign:'',textBaseline:'',measureText:()=>({width:0}),
      fillRect(x,y,w,h){this.box={rect:[x,y-220,w,h],colour:minimapColour(this.fillStyle)};},
      fillText(text,x,y){this.text={text,position:[x,y-220],colour:minimapColour(this.fillStyle)};}};
    legend.call({mmMode:mode},ctx,250,220,{x0:0,x1:width});
    return {mode,width,box:ctx.box,text:ctx.text,font:ctx.font,align:ctx.textAlign,baseline:ctx.textBaseline};
  }
  const labels=[];
  for(const mode of ['full','near'])for(const width of [0,.49,.5,139.5,679.9,10000.5])labels.push(label(mode,width));
  const full=label('full',123),near=label('near',123),font=/^([\d.]+)px (.+)$/.exec(full.font);
  if(!font||full.align!=='left'||full.baseline!=='bottom')throw new Error('Unsupported original minimap legend typography');
  return {rules:{cadence:{warm:Number(warm[1]),warmGate:Number(gate[1]),gate:Number(gate[2])},
    labels:{full:full.text.text,near:near.text.text.replace('123','%d'),box:full.box,
      position:full.text.position,colours:{full:full.text.colour,near:near.text.colour},fontSize:Number(font[1]),fontFamily:font[2]}},
    fixtures:{minimapCadence:cadence,minimapLabels:labels}};
}
