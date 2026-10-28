import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const generator='tools/campaign_backdrop_capture.mjs';
const generatorHash=digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'));
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const sourceInputs={};
for(const path of ['public/css/style.css','public/js/prologue.js','public/js/chapterScenes.js','public/js/story.js']){
  const bytes=await readFile(join(source,path));
  sourceInputs[path]=digest(bytes);
  if(provenance.inputs?.[path]!==sourceInputs[path])throw new Error('Refresh shared source metadata first: '+path);
}
const css=await readFile(join(source,'public/css/style.css'),'utf8');
const {PrologueIntroController}=await import(pathToFileURL(join(source,'public/js/prologue.js')).href);
const method=PrologueIntroController.prototype.initDOM.toString();
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
const sizes=[[320,568],[568,320],[500,500],[375,812],[640,360],[720,450],[1024,768],
  [1440,900],[1920,1080],[1080,1920],[3840,2160],[1,1]];
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
      const stage=document.querySelector('.prologue-stage'),backdrop=document.querySelector('.prologue-bg-blur');
      const style=getComputedStyle(backdrop),rect=backdrop.getBoundingClientRect(),stageRect=stage.getBoundingClientRect();
      const matrix=new DOMMatrixReadOnly(style.transform),insets=[style.top,style.right,style.bottom,style.left].map(parseFloat);
      if(!insets.every(value=>value===insets[0])||insets[0]>0||matrix.a!==matrix.d||matrix.b||matrix.c
        ||style.backgroundSize!=='cover')throw new Error('Unsupported original cinematic backdrop geometry');
      return {rules:{inset:-insets[0],scale:matrix.a},stage:[stageRect.x,stageRect.y,stageRect.width,stageRect.height],
        backdrop:[rect.x,rect.y,rect.width,rect.height],layout:[parseFloat(style.width),parseFloat(style.height)],filter:style.filter};
    },{css,method});
    if(rules&&JSON.stringify(sample.rules)!==JSON.stringify(rules))throw new Error('Backdrop rules vary across source viewports');
    rules=sample.rules;
    cases.push({size:[width,height],stage:sample.stage,backdrop:sample.backdrop,layout:sample.layout,filter:sample.filter});
  }
}finally{await browser.close();}
for(const [path,expected] of Object.entries(sourceInputs))
  if(digest(await readFile(join(source,path)))!==expected)throw new Error('Source changed during backdrop capture: '+path);
if(digest((await readFile(join(root,generator),'utf8')).replace(/\r\n?/g,'\n'))!==generatorHash)
  throw new Error('Campaign backdrop generator changed during capture');
const input={formatVersion:1,source:{inputs:{[generator]:generatorHash},sourceInputs},rules};
await writeFixtureJson(join(root,'data/campaign_backdrop.json'),input);
await writeFixtureJson(join(root,'tests/fixtures/campaign_backdrop.json'),{...input,browser:browser.version(),cases});
console.log('CAMPAIGN_BACKDROP_REFERENCES_PASS cases='+cases.length);
