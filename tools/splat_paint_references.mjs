// Original DOM callbacks supply immutable layout/decimal serialization and source gradient/filter metadata.
export function captureSplatPaint({mainSource,css}) {
  const start=mainSource.indexOf('blood: (list) => {'),glint=mainSource.indexOf('glint: (list) => {',start),end=mainSource.indexOf('ccFlash: (a) => {',glint);
  if(start<0||glint<=start||end<=glint)throw new Error('Missing original glass overlay HUD callbacks');
  const rules={};
  for(const [kind,selector,body]of [['blood','blood-splat',mainSource.slice(start,glint)],['glint','glint-flash',mainSource.slice(glint,end)]]) {
    const style=new RegExp('\\.'+selector+'\\s*\\{([^}]+)\\}').exec(css)?.[1];
    const width=/width:\s*([\d.]+)vmin/.exec(style??''),blur=/blur\(([\d.]+)vmin\)/.exec(style??'');
    const shadow=/drop-shadow\(0 0 ([\d.]+)vmin rgba\(([^)]+)\)\)/.exec(style??'');
    const stops=[...body.matchAll(/rgba\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\)\s*([\d.]+)%/g)]
      .map(match=>({at:Number(match[5])/100,color:[Number(match[1])/255,Number(match[2])/255,Number(match[3])/255,Number(match[4])]}));
    if(!width||!blur||!shadow||stops.length!==4)throw new Error('Missing source glass gradient/filter: '+kind);
    const color=shadow[2].split(',').map(Number);
    rules[kind]={extent:Number(width[1]),blur:Number(blur[1]),shadowBlur:Number(shadow[1]),
      shadowColor:[color[0]/255,color[1]/255,color[2]/255,color[3]],stops};
  }
  const boxes={bloodVig:document.createElement('div'),glintVig:document.createElement('div')};
  const callbacks=new Function('$','return ({'+mainSource.slice(start,end)+'});')(id=>boxes[id]);
  const frames=[];
  for(const list of [[{id:1,u:.123456,v:.765432,drops:[{x:-2.675,y:.125,r:1.005},{x:2.675,y:-.125,r:7}],a:.6255}],
    [{id:1,u:.8,v:.2,drops:[{x:99,y:99,r:99}],a:.1235},{id:2,u:.5,v:.5,drops:[],a:2}],[],[]]) {
    callbacks.blood(list);callbacks.glint(list);
    const result={};
    for(const [kind,key]of [['blood','bloodVig'],['glint','glintVig']])result[kind]=[...boxes[key].children].map(element=>({
      id:Number(element.dataset.bid),left:parseFloat(element.style.left)/100,top:parseFloat(element.style.top)/100,
      opacity:Number(element.style.opacity),background:element.style.backgroundImage}));
    frames.push({list,result});
  }
  const decimals=[];
  for(const value of [-2.675,-1.005,-.125,-.005,0,.005,.125,1.005,2.675,12.555,.999999,1e-20])for(const digits of [0,1,2,3])
    decimals.push({value,digits,result:Number(value.toFixed(digits))});
  return {rules,fixtures:{splatPaintFrames:frames,cssDecimal:decimals}};
}

export async function captureSplatRasters(page,mainSource,css) {
  const cases=[];
  const entries=[{id:1,u:.48,v:.47,a:.6255,drops:[{x:0,y:0,r:4.6},{x:-2.675,y:.125,r:1.005},{x:3.5,y:-4.25,r:2.2}]},
    {id:2,u:.53,v:.52,a:.85,drops:[{x:0,y:0,r:7},{x:4.3,y:3.2,r:1.4}]}];
  for(const viewport of [{width:640,height:360},{width:360,height:640}])for(const kind of ['blood','glint','both']) {
    await page.setViewportSize(viewport);
    await page.evaluate(({mainSource,css,kind,entries})=>{
      document.body.replaceChildren();
      const style=document.createElement('style');
      style.textContent=['blood-vig','glint-vig','blood-splat','glint-flash'].map(key=>
        new RegExp('\\.'+key+'\\s*\\{[^}]+\\}').exec(css)?.[0]??'').join('\n')+
        '\nhtml,body{margin:0;background:transparent;width:100%;height:100%;overflow:hidden;}';
      document.body.append(style);
      const boxes={};
      for(const key of ['bloodVig','glintVig']) {
        const box=document.createElement('div');box.className=key==='bloodVig'?'blood-vig':'glint-vig';
        document.body.append(box);boxes[key]=box;
      }
      const start=mainSource.indexOf('blood: (list) => {'),end=mainSource.indexOf('ccFlash: (a) => {',start);
      const callbacks=new Function('$','return ({'+mainSource.slice(start,end)+'});')(id=>boxes[id]);
      if(kind!=='glint')callbacks.blood(entries);
      if(kind!=='blood')callbacks.glint(entries);
    },{mainSource,css,kind,entries});
    const png=await page.screenshot({omitBackground:true,animations:'disabled'});
    cases.push({viewport,kind,entries,png:png.toString('base64')});
  }
  return cases;
}
