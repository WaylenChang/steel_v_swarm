import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {writeFixtureJson} from './fixture_json.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=resolve(process.env.SVS_SOURCE||join(root,'..','steel_vs_swarm'));
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const provenance=JSON.parse(await readFile(join(root,'data/provenance.json'),'utf8'));
const balanceBytes=await readFile(join(root,'data/balance.json'));
const balance=JSON.parse(balanceBytes);
const sourceInputs={};
for(const path of ['public/js/game.js','tools/audit_src.mjs']){
  sourceInputs[path]=digest(await readFile(join(source,path)));
  if(provenance.inputs[path]!==sourceInputs[path])throw new Error('Original spectator input changed: '+path);
}
const game=(await readFile(join(source,'public/js/game.js'),'utf8')).replace(/\r\n?/g,'\n');
const {grabMethod}=await import(pathToFileURL(join(source,'tools/audit_src.mjs')).href);
const method=grabMethod(game,'_specHud');
const character='s01',hero=balance.heroes[character],display=balance.spectator.display[character];
const definitions={weapon:Object.fromEntries(['light','heavy'].map(slot=>[slot,hero.weapons[slot][0]])),
  ability:Object.fromEntries(['def','atk'].map(slot=>[slot,hero.abilities[slot][0]]))};
const base={pid:'17',hero:true,act:true,side:'SWARM',ch:character,hp:37,max:100};
const inputs=[
  {name:'missing',fields:{}},
  {name:'nulls',fields:{ab:null,cds:null,mp:null,mm:null,sp:null,maxSp:null,rs:null,money:null,kn:null,emp:null,up:null}},
  {name:'zeroes',fields:{ab:{light:0,heavy:0,def:0,atk:0},cds:[0,0],mp:0,mm:0,sp:0,maxSp:0,rs:0,money:0,kn:0,emp:0,up:0}},
  {name:'partial-cooldowns',fields:{ab:{},cds:[null,2.5],mp:1000,mm:1500,sp:14,maxSp:90,up:{}}},
  {name:'negative-values',fields:{ab:{light:1,heavy:1,def:1,atk:1},cds:[-1,0],mp:-5,mm:-2,sp:-3,maxSp:-4,rs:-6,money:-7,kn:-8,emp:-9,up:{lw:2}}},
  {name:'nan-cooldown',fields:{ab:{def:1,atk:1},cds:['NaN',0],mp:1000}},
];
const {chromiumOrNull,chromePath}=await import(pathToFileURL(join(source,'tools/pw.mjs')).href);
const chromium=await chromiumOrNull();
if(!chromium||!chromePath())throw new Error('Original development Chromium and Playwright are required');
const browser=await chromium.launch({headless:true,executablePath:chromePath()});
let programs;
try{
  const page=await browser.newPage();
  programs=await page.evaluate(({method,base,inputs,definitions,display})=>{
    const Client=new Function('SPEC_CAM','CHARACTERS','SIDES','heroWeapon','heroAbility','return class {'+method+'}')(
      {NAMES:{god:'god',fpv:'fpv'}},{s01:display},{SWARM:{hero:'drone'}},
      (_ch,slot)=>definitions.weapon[slot],(_ch,slot)=>definitions.ability[slot]);
    return inputs.map(input=>{
      const actor={...base,...input.fields};
      if(Array.isArray(actor.cds))actor.cds=actor.cds.map(value=>value==='NaN'?NaN:value);
      const client=Object.assign(new Client(),{side:'',_specPid:'17',_specView:'fpv',
        _specRoster:()=>[actor],_specName:()=>'controlled'});
      const hud=client._specHud();
      const keys=['mp','mm','sp','msp','rs','money','kn','emp','upg','lift','mobil','morph','light','heavy','def','atk'];
      return {...input,result:Object.fromEntries(keys.map(key=>[key,hud[key]]))};
    });
  },{method,base,inputs,definitions,display});
}finally{await browser.close();}
for(const [path,hash] of Object.entries(sourceInputs))if(digest(await readFile(join(source,path)))!==hash)throw new Error('Original spectator input changed during capture: '+path);
const inputsHash={'data/balance.json':digest(balanceBytes)};
for(const path of ['tools/spectator_hud_defaults_capture.mjs','tools/fixture_json.mjs'])
  inputsHash[path]=digest((await readFile(join(root,path),'utf8')).replace(/\r\n?/g,'\n'));
await writeFixtureJson(join(root,'tests/fixtures/spectator_hud_defaults.json'),
  {formatVersion:1,source:{inputs:inputsHash,sourceInputs},browser:browser.version(),base,programs});
console.log('SPECTATOR_HUD_DEFAULTS_CAPTURE_PASS programs='+programs.length);
