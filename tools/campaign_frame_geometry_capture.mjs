import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/campaign_frame_geometry_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js','tools/audit_src.mjs']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController,PROLOGUE_SCENES}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const {grabFn}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const prologue=(await readFile(join(source,'public/js/prologue.js'),'utf8')).replace(/\r\n?/g,'\n');
const cameraFunctions=['easeInOutQuad','isLandscape','calcCameraTransform'].map(name=>grabFn(prologue,name)).join('\n');
const method=PrologueIntroController.prototype.initDOM.toString();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const sizes=[[320,568],[568,320],[500,500],[375,812],[640,360],[720,450],[1024,768],
  [1440,900],[1920,1080],[1080,1920],[3840,2160],[1,1],[501,500],[377,376],[641,640],[2,1],[3,2]];
let rules;const cases=[];
try{
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const [width,height] of sizes){
    await page.setViewportSize({width,height});
    const sample=await page.evaluate(({css,method})=>{
      document.head.innerHTML='<style></style>';document.head.firstChild.textContent=css;
      document.body.innerHTML='<div class="prologue-stage"><div class="prologue-scenes" id="prologueScenes"></div></div>';
      const prototype=new Function(`return {${method}};`)();
      const context=Object.assign(Object.create(prototype),{root:document.querySelector('.prologue-stage'),
        scenesContainer:document.getElementById('prologueScenes'),content:null,
        scenes:[{id:'geometry',img:'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg"/%3E'}]});
      context.initDOM();
      const item=document.querySelector('.prologue-scene-item'),backdrop=document.querySelector('.prologue-bg-blur');
      const frame=document.querySelector('.prologue-fg-frame'),image=document.querySelector('.prologue-fg-art');
      item.style.transition='none';item.style.opacity='1';backdrop.style.display='none';frame.style.boxShadow='none';
      image.style.transition='none';image.style.background='rgb(48, 144, 208)';
      const find=(rules,selector,property)=>{
        for(const rule of rules){
          if(rule.selectorText===selector&&rule.style?.getPropertyValue(property))return rule.style.getPropertyValue(property);
          if(rule.cssRules){const nested=find(rule.cssRules,selector,property);if(nested)return nested;}
        }
        return null;
      };
      const inset=find(document.styleSheets[0].cssRules,'.prologue-fg-art','inset');
      const maxWidth=find(document.styleSheets[0].cssRules,'.prologue-fg-frame','max-width');
      if(!/^-[\d.]+%$/.test(inset))throw new Error('Unsupported original foreground inset');
      if(!/^[\d.]+vw$/.test(maxWidth))throw new Error('Unsupported original frame width');
      const geometry=element=>{const r=element.getBoundingClientRect();return [r.x,r.y,r.width,r.height];};
      const style=getComputedStyle(frame),border=[style.borderTopWidth,style.borderRightWidth,style.borderBottomWidth,style.borderLeftWidth].map(parseFloat);
      return {inset:-parseFloat(inset)/100,maxWidthRatio:parseFloat(maxWidth)/100,frame:geometry(frame),image:geometry(image),border,
        borderColor:style.borderLeftColor,maxWidth:style.maxWidth};
    },{css,method});
    if(width>height){
      const match=sample.borderColor.match(/^rgba\((\d+), (\d+), (\d+), ([\d.]+)\)$/);
      if(!match||sample.border[1]!==sample.border[3]||sample.border[0]||sample.border[2])
        throw new Error('Unsupported original foreground borders: '+JSON.stringify({size:[width,height],...sample}));
      const next={inset:sample.inset,maxWidthRatio:sample.maxWidthRatio,
        borderWidth:sample.border[1],borderColor:[...match.slice(1,4).map(value=>Number(value)/255),Number(match[4])]};
      if(rules&&JSON.stringify(next)!==JSON.stringify(rules))throw new Error('Foreground rules vary across source viewports');
      rules=next;
    }
    const row={size:[width,height],frame:sample.frame,image:sample.image,border:sample.border};
    if([[320,568],[568,320],[500,500],[501,500],[377,376],[641,640]].some(([w,h])=>w===width&&h===height))
      row.png=(await page.screenshot()).toString('base64');
    row.poses=await page.evaluate(({cameraFunctions,camera})=>{
      const calculate=new Function(`${cameraFunctions}\nreturn calcCameraTransform;`)();
      const image=document.querySelector('.prologue-fg-art');
      return [0,.5,1].map(progress=>{
        const transform=calculate(camera,progress);
        const match=transform.match(/translate3d\(([-\d.]+)%, ([-\d.]+)%, 0\) scale\(([\d.]+)\)/);
        if(!match)throw new Error('Unsupported original foreground camera transform: '+transform);
        image.style.transform=transform;
        const rect=image.getBoundingClientRect();
        return {progress,target:{x:Number(match[1]),y:Number(match[2]),scale:Number(match[3])},
          image:[rect.x,rect.y,rect.width,rect.height]};
      });
    },{cameraFunctions,camera:PROLOGUE_SCENES[0].camera});
    cases.push(row);
  }
}finally{await browser.close();}
const units=[1,2,4,8,16,32,64,128,256,512,1024].find(value=>cases.every(row=>{
  const offsets=[row.image[0]-row.frame[0]-row.border[3],row.image[1]-row.frame[1]-row.border[0]];
  return offsets.every(offset=>Math.abs(offset*value-Math.round(offset*value))<1e-7);
}));
if(!units)throw new Error('Cannot identify original foreground layout units');
rules.layoutUnits=units;
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during frame capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Campaign foreground generator changed during capture');
const input={formatVersion:1,source:{inputs:{[generator]:generatorHash},sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_frame_geometry.json'),input);
await writeFixtureJson(join(root,'tests/fixtures/campaign_frame_geometry.json'),{...input,browser:browser.version(),cases});
console.log('CAMPAIGN_FRAME_GEOMETRY_REFERENCES_PASS cases='+cases.length);
