// Browser CSS supplies the native death rim geometry and per-keyframe easing oracle.
export function captureDeathOverlay({css}) {
  const selector=name=>new RegExp('\\.'+name+'\\s*\\{[^}]+\\}').exec(css)?.[0];
  const rim=selector('death-alert'),flash=selector('death-flash');
  const rimOn=/\.death-alert\.on\s*\{[^}]+\}/.exec(css)?.[0];
  const flashOn=/\.death-flash\.on\s*\{[^}]+\}/.exec(css)?.[0];
  const pulse=/@keyframes deathPulse[^\n]+/.exec(css)?.[0],white=/@keyframes deathWhiteout[^\n]+/.exec(css)?.[0];
  const shadow=/inset\s+0\s+0\s+([\d.]+)px\s+([\d.]+)px\s+rgba\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/.exec(rim??'');
  const pulseDuration=/deathPulse\s+([\d.]+)s\s+ease-in-out/.exec(rimOn??'');
  const flashDuration=/deathWhiteout\s+([\d.]+)s\s+ease-out/.exec(flashOn??'');
  const peak=/([\d.]+)%\s*\{\s*opacity:\s*([\d.]+)/.exec(white?.slice(white.indexOf('}')+1))??null;
  const low=/0%,\s*100%\s*\{\s*opacity:\s*([\d.]+)/.exec(pulse??'');
  const high=/50%\s*\{\s*opacity:\s*([\d.]+)/.exec(pulse??'');
  if(!rim||!flash||!rimOn||!flashOn||!pulse||!white||!shadow||!pulseDuration||!flashDuration||!peak||!low||!high)
    throw new Error('Missing original death rim/whiteout CSS');
  const rules={blur:Number(shadow[1]),spread:Number(shadow[2]),color:[Number(shadow[3])/255,Number(shadow[4])/255,Number(shadow[5])/255,Number(shadow[6])],
    pulseDuration:Number(pulseDuration[1]),flashDuration:Number(flashDuration[1]),flashPeak:Number(peak[1])/100,flashAlpha:Number(peak[2]),
    low:Number(low[1]),high:Number(high[1])};
  rules.layers={};
  const sheet=new CSSStyleSheet();sheet.replaceSync(css);
  for(const [key,name]of Object.entries({rim:'death-alert',flash:'death-flash',hud:'hud-top',menu:'overlay',shop:'shop-overlay',dialogue:'dlg-layer',touch:'touch-layer'})) {
    const layer=Array.from(sheet.cssRules).find(rule=>rule.selectorText==='.'+name)?.style.zIndex;
    if(!/^\d+$/.test(layer??''))throw new Error('Missing original death overlay stacking layer: '+name);
    rules.layers[key]=Number(layer);
  }
  const style=document.createElement('style');style.textContent=[rim,flash,rimOn,flashOn,pulse,white].join('\n');document.head.append(style);
  const opacity=[];
  try {
    for(const kind of ['alert','flash']) {
      const element=document.createElement('div');element.className='death-'+kind+' on';document.body.append(element);
      try {
        const animation=element.getAnimations()[0];if(!animation)throw new Error('Original death animation did not bind');
        animation.pause();
        for(const time of [-.01,0,.01,.04,.1,.175,.35,.399999,.4,.525,.7,.875,1.4]) {
          animation.currentTime=time*1000;opacity.push({kind,time,value:Number(getComputedStyle(element).opacity)});
        }
      } finally {element.remove();}
    }
  } finally {style.remove();}
  return {rules,fixtures:{deathOverlayOpacity:opacity}};
}

export async function captureDeathOverlayRasters(page,css) {
  const cases=[];
  for(const viewport of [{width:640,height:360},{width:360,height:640},{width:128,height:128}])for(const kind of ['rim','flash']) {
    await page.setViewportSize(viewport);
    await page.evaluate(({css,kind})=>{
      document.body.replaceChildren();
      const style=document.createElement('style');
      style.textContent=['death-alert','death-flash'].map(name=>new RegExp('\\.'+name+'\\s*\\{[^}]+\\}').exec(css)?.[0]??'').join('\n')+
        '\nhtml,body{margin:0;background:transparent;width:100%;height:100%;overflow:hidden;}';
      document.body.append(style);
      const element=document.createElement('div');element.className=kind==='rim'?'death-alert':'death-flash';
      element.style.opacity=kind==='rim'?'1':'.92';document.body.append(element);
    },{css,kind});
    const png=await page.screenshot({omitBackground:true});
    cases.push({viewport,kind,opacity:kind==='rim'?1:.92,png:png.toString('base64')});
  }
  return cases;
}
