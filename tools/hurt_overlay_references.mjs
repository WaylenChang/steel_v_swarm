// Browser CSS supplies opacity timing; original _reflash supplies repeated-hit admission.
export function captureHurtOverlay({css,reflashSource}) {
  const base=/\.hurt-vig\s*\{[^}]+\}/.exec(css)?.[0];
  const animation=/\.hurt-vig\.on\s*\{[^}]+\}/.exec(css)?.[0];
  const keys=/@keyframes hurtFlash[^\n]+/.exec(css)?.[0];
  const duration=/hurtFlash\s+([\d.]+)s\s+ease-out/.exec(animation??'');
  const inner=/transparent\s+([\d.]+)%/.exec(base??'');
  const color=/rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)/.exec(base??'');
  const peak=/([\d.]+)%\s*\{\s*opacity:\s*1\s*;?\s*\}/.exec(keys??'');
  if(!base||!animation||!keys||!duration||!inner||!color||!peak)throw new Error('Missing original hurt-vignette CSS');
  const rules={duration:Number(duration[1]),inner:Number(inner[1])/100,peak:Number(peak[1])/100,
    color:[Number(color[1])/255,Number(color[2])/255,Number(color[3])/255,Number(color[4])]};
  const style=document.createElement('style'),element=document.createElement('div');
  style.textContent=base+'\n'+animation+'\n'+keys;document.head.append(style);
  element.className='hurt-vig on';document.body.append(element);
  const opacity=[];
  try {
    const motion=element.getAnimations()[0];if(!motion)throw new Error('Original hurt animation did not bind');
    motion.pause();
    for(const time of [-.01,0,.01,.04,.079999,.08,.1,.2,.4,.499999,.5,.6]) {
      motion.currentTime=time*1000;opacity.push({time,value:Number(getComputedStyle(element).opacity)});
    }
  } finally {element.remove();style.remove();}
  let now=1;
  const reflash=new Function('performance',reflashSource+'\nreturn _reflash;')({now:()=>now*1000});
  const classes=new Set(),listeners={},target={classList:{contains:key=>classes.has(key),add:key=>classes.add(key),remove:key=>classes.delete(key)},
    offsetWidth:1,addEventListener:(event,callback)=>{listeners[event]=callback;}};
  const flashes=[];
  for(const action of [{at:1},{at:1.1},{at:1.5,end:true},{at:1.6},{at:1.8},{at:2.1,end:true},{at:5},{at:5.2},{at:6.01}]) {
    now=action.at;
    if(action.end)listeners.animationend();else reflash(target,rules.duration*1000);
    flashes.push({...action,active:classes.has('on'),started:(target._rfAt??0)/1000});
  }
  return {rules,fixtures:{hurtOpacity:opacity,hurtReflash:flashes}};
}
