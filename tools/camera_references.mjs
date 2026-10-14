import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Execute source view/camera seams offline; runtime consumes scalar profiles and native collision.
export async function cameraReferences(d, source, gameSource) {
  const THREE = await import(pathToFileURL(join(source, 'out/forest_review/three.module.js')).href);
  const text = gameSource.replace(/\r\n/g, '\n');
  const shapeStart = text.indexOf('const VIEW_SHAPE = '), shapeEnd = text.indexOf('\nconst VIEW_DEF = ', shapeStart);
  const defaultEnd = text.indexOf(';', shapeEnd);
  const flyStart = text.indexOf('const VIEW_FLY_F = '), viewEnd = text.indexOf('\n};', flyStart);
  if (shapeStart < 0 || shapeEnd < 0 || flyStart < 0 || viewEnd < 0) throw new Error('Missing source heroView');
  const heroView = new Function('CHARACTERS', 'SELF_F', text.slice(shapeStart, defaultEnd + 1) +
    text.slice(flyStart, viewEnd + 3) + '\nreturn heroView;')(d.CHARACTERS, d.SELF_F);
  const scope = { THREE, ...d, heroView };
  const method = name => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing source camera method: ${name}`);
    const lineEnd = text.indexOf('\n', start + 1);
    const finish = text.slice(start + 1, lineEnd).trimEnd().endsWith('}') ? lineEnd : end + 4;
    return new Function(...Object.keys(scope), `return function ${text.slice(start + 1, finish).trimStart().slice(name.length)}`)(...Object.values(scope));
  };
  const selfStart = text.indexOf('\n  get selfH() {'), selfEnd = text.indexOf('\n  }\n', selfStart);
  if (selfStart < 0 || selfEnd < 0) throw new Error('Missing source selfH');
  const selfHeight = new Function(...Object.keys(scope), `return function ${text.slice(selfStart + 1, selfEnd + 4).trimStart().slice('get selfH'.length)}`)(...Object.values(scope));
  const eye = method('_eyeH'), flying = method('_flying'), deClip = method('_cameraDeClip'), pull = method('_cameraPullSegment');
  const rules = {};
  const grab = (pattern, key, sourceText = text) => {const match=pattern.exec(sourceText);if(!match)throw new Error(`Missing camera rule ${key}`);rules[key]=Number(match[1]);};
  grab(/const SKIN = ([\d.]+);/, 'skin', deClip.toString());
  grab(/\(hit - ([\d.]+)\) \/ len/, 'pullClearance');
  grab(/py < s \+ ([\d.]+)/, 'surfaceClearance');
  grab(/\(i - 1\) \/ N - ([\d.]+)/, 'surfaceRetreat');
  grab(/new THREE\.PerspectiveCamera\(fov, this\.canvas\.clientWidth \/ this\.canvas\.clientHeight, ([\d.]+),/, 'near');
  const profiles={}, cameraAnchors=[], cameraClips=[];
  for (const [character,hero] of Object.entries(d.CHARACTERS)) {
    profiles[character]={};
    for (const flight of [false,true]) {
      const ctx={heroKind:hero.kind,ch:character,side:hero.side==='MERC'?'STEEL':hero.side,upg:{super:0},isDrone:hero.kind==='drone',isMorph:hero.kind==='morph',flight,charge:0,_flying:flying};
      ctx.selfH=selfHeight.call(ctx);
      const view=heroView(hero.kind,character,flying.call(ctx));
      const height=eye.call(ctx);ctx.charge=1;
      profiles[character][flight?'air':'ground']={eye:height,forward:ctx.selfH*view.f,crouch:height-eye.call(ctx)};
      for (const yaw of [0,.7,-1.2]) for (const charge of [0,.5,1]) {
        ctx.charge=charge;
        const position=[12,50,-9], h=eye.call(ctx), forward=ctx.selfH*view.f;
        cameraAnchors.push({character,flight,yaw,charge,position,eye:h,
          result:[position[0]-Math.sin(yaw)*forward,position[1]+h,position[2]-Math.cos(yaw)*forward]});
      }
    }
  }
  const scenarios=[
    {name:'clear',camera:[0,5,-5]}, {name:'zero horizontal reach',camera:[.0005,8,0]},
    {name:'cylinder before camera',camera:[0,5,-5],blockers:[{x:0,z:-4,y:0,h:12,r:.8}]},
    {name:'cylinder inside skin',camera:[0,5,-5],blockers:[{x:0,z:-1,y:0,h:12,r:.8}]},
    {name:'cylinder tangent',camera:[0,5,-5],blockers:[{x:2,z:-3,y:0,h:12,r:.8}]},
    {name:'box front',camera:[0,5,-5],blockers:[{x:0,z:-4,y:0,h:12,hw2:.5,hd2:1,ry:0}]},
    {name:'rotated box corner',camera:[-5,5,-5],blockers:[{x:-3,z:-3,y:0,h:12,hw2:.8,hd2:2,ry:.7}]},
    {name:'box parallel axis outside',camera:[0,5,-5],blockers:[{x:5,z:-3,y:0,h:12,hw2:.5,hd2:1,ry:0}]},
    {name:'vertical miss',camera:[0,13,-5],blockers:[{x:0,z:-4,y:0,h:12,r:.8}]},
    {name:'below deck ignored',camera:[0,5,-5],onDeck:true,surface:20,blockers:[{x:0,z:-4,y:0,h:12,r:.8}]},
    {name:'dynamic obstacle',camera:[0,5,-5],entities:[{x:0,z:-4,y:0,colR:.8,colH:12}]},
    {name:'self dynamic obstacle ignored',camera:[0,5,-5],entities:[{x:0,z:-1,y:0,colR:.8,colH:12,isSelf:true}]},
    {name:'3D short cut',camera:[0,5,-5],hit:1}, {name:'3D partial cut',camera:[0,8,-8],hit:6},
    {name:'source floor sample',camera:[0,1,-5],ground:0}, {name:'non-finite surface ignored',camera:[0,5,-5],ground:null},
    {name:'ridge sample',camera:[0,5,-9],ridge:true}, {name:'far blocker ignored',camera:[0,5,-5],blockers:[{x:100,z:-3,y:0,h:12,r:60}]},
  ];
  for (const scenario of scenarios) for (const yaw of [0,.7,Math.PI/2]) {
    const turn=p=>new THREE.Vector3(p[0],p[1],p[2]).applyAxisAngle(new THREE.Vector3(0,1,0),yaw);
    const camera=turn(scenario.camera), blockers=(scenario.blockers||[]).map(b=>{const p=turn([b.x,b.y,b.z]);return {...b,x:p.x,z:p.z,ry:(b.ry||0)+yaw};});
    const entities=(scenario.entities||[]).map(e=>{const p=turn([e.x,e.y,e.z]);return {...e,mesh:{position:p}};});
    const surface=(x,z)=>scenario.ground===null?NaN:scenario.ridge&&Math.hypot(x,z)>3?5:(scenario.ground||0);
    const ctx={camera:{position:camera},pos:new THREE.Vector3(),viewMode:'fpv',_eyeH:()=>5,_onDeck:!!scenario.onDeck,
      _surfHere:scenario.surface||0,_blockersNear:()=>blockers,ents:new Map(entities.map((e,i)=>[i,e])),
      _blockerHitT:()=>scenario.hit??null,_surf:surface,_cameraPullSegment:pull};
    const initial=camera.toArray();deClip.call(ctx);
    cameraClips.push({name:scenario.name,camera:initial,eye:5,blockers,entities:entities.map(e=>({...e,mesh:undefined,position:e.mesh.position.toArray()})),
      onDeck:!!scenario.onDeck,surface:scenario.surface||0,hit:scenario.hit??null,ground:scenario.ground??(scenario.ground===null?null:0),ridge:!!scenario.ridge,result:camera.toArray()});
  }
  return {profiles,rules,fixtures:{cameraAnchors,cameraClips}};
}
