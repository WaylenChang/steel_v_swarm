import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.argv[2]||process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const cssPath='public/css/style.css',css=await readFile(join(source,cssPath));
if(provenance.inputs?.[cssPath]!==digest(css))throw new Error('Refresh shared source CSS metadata first');
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium)throw new Error('Original development Playwright runtime is required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
try {
  const page=await browser.newPage();
  const programs=await page.evaluate(async css=>{
    const style=document.createElement('style');style.textContent=css;document.head.append(style);
    const programs=[];
    for(const [channel,name]of [['fire','env-fog'],['weather','weather-fog']]) {
      for(const commands of [
        [[1,[0,.01,.04,.1,.2,.35,.5]],[0,[0,.04,.15,.35,.5]]],
        [[1,[0,.04,.1]],[0,[0,.01,.03]],[1,[0,.01,.05,.2,.5]]],
        [[.75,[0,.04,.1]],[.2,[0,.04,.1]],[.9,[0,.04,.1]],[0,[0,.04,.2,.5]]],
        [[1,[0,.04]],[1,[.08,.1]],[0,[0,.01,.03,.1,.5]]],
        [[0,[0,.1]],[1,[0]],[0,[0,.01]],[1,[0,.04,.5]]],
      ]) {
        const element=document.createElement('div');element.className=name;document.body.append(element);
        getComputedStyle(element).opacity;
        const duration=parseFloat(getComputedStyle(element).transitionDuration),frames=[];
        let previous=null;
        for(const [target,samples]of commands) {
          element.style.opacity=String(target);getComputedStyle(element).opacity;
          const animation=element.getAnimations()[0];
          if(animation)animation.pause();
          for(const time of samples) {
            if(animation)animation.currentTime=time*1000;
            frames.push({target,time,newTransition:animation!==previous,
              duration:animation?animation.effect.getComputedTiming().duration/1000:0,
              opacity:Number(getComputedStyle(element).opacity)});
            previous=animation;
          }
        }
        programs.push({channel,duration,frames});element.remove();
      }
    }
    style.remove();return programs;
  },css.toString('utf8'));
  if(digest(await readFile(join(source,cssPath)))!==digest(css))throw new Error('CSS changed during transition capture');
  const file='tools/scope_transition_capture.mjs';
  const inputs={[file]:digest((await readFile(join(root,file),'utf8')).replace(/\r\n?/g,'\n'))};
  await mkdir(join(root,'tests/fixtures'),{recursive:true});
  await writeFixtureJson(join(root,'tests/fixtures/scope_transition.json'),{formatVersion:1,
    source:{inputs,sourceInputs:{[cssPath]:digest(css)}},browser:browser.version(),programs});
  console.log('SCOPE_TRANSITION_REFERENCES_PASS programs='+programs.length);
} finally {await browser.close();}
