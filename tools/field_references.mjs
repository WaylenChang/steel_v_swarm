import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Execute original persistent field seams; climate, terrain and shaders have separate oracles.
export async function fieldReferences(d, BattleSim, config, source) {
  const template=new BattleSim(config);
  const actor=(id,character,side='STEEL',x=0,z=0)=>({id,pid:id,ch:character,hero:true,kind:d.CHARACTERS[character].kind,
    side,x,z,y:0,hp:1000,maxHp:1000,sp:30,maxSp:500,mp:1000,maxMp:1000,armor:0,dead:false,
    abil:{light:1,heavy:1,def:1,atk:1},mods:[],buffs:{},acd:{},achg:{}});
  const context=actors=>Object.assign(Object.create(template),{t:10,over:false,events:[],fogs:[],cubicSlabs:[],trees:[],darkMoons:[],
    ents:new Map(actors.map(a=>[a.id,a])),heroes:new Map(actors.map(a=>[a.pid,a])),_visMemo:null,_tickN:1,
    curWeatherDyn:null,curWeatherVec:{fog:0},weatherSurface:null});
  const summary=s=>({position:[s.x,s.y||0,-s.z],hp:s.hp,max_hp:s.maxHp,radius:d.hitR(s),height:d.hitH(s),
    angle:s.ang,until:s.until,effect_radius:s.r});
  const fieldCube=[];
  for(let level=1;level<=4;level++)for(const fraction of [0,.0625,.25,1]) {
    const h=actor(1,'t10'),enemy=actor(2,'s09','SWARM',0,3),s=context([h,enemy]),A=d.heroAbility('t10','def',level);
    const hits=[];s._damage=(target,amount,by,pen)=>hits.push({target:target.id,amount,pen});
    s._castEffect(h,A,0,0,fraction,null,true);
    const cage=s.cubicSlabs[0],slabs=cage.slabs.map(summary),steps=[];
    for(const [index,now] of [10.1,10.2,10+A.dur,10+A.dur+.1].entries()) {
      s.t=now;
      if(index===1)for(let k=0;k<cage.slabs.length;k++)if(k%2===0){cage.slabs[k].hp=0;cage.slabs[k].dead=true;s.ents.delete(cage.slabs[k].id);}
      s._tickCubicSlabs(.1);
      steps.push({now,damage:hits.splice(0),cages:s.cubicSlabs.length,live:cage.slabs.filter(v=>s.ents.has(v.id)&&v.hp>0&&!v.dead).map(v=>v.ang)});
    }
    fieldCube.push({level,fraction,slabs,dps:cage.dps,radius:cage.r,until:cage.until,steps});
  }
  const fieldFog=[];
  for(const character of ['m04','m05'])for(let level=1;level<=4;level++)for(const fraction of [0,.25,1])for(const outside of [false,true]) {
    const h=actor(1,character),A=d.heroAbility(character,'def',level),enemy=actor(2,'s09','SWARM',(A.r||35)+(outside?1.01:1),0);
    const s=context([h,enemy]),hits=[];
    s._damage=(target,amount,by,pen)=>hits.push({target:target.id,amount,pen});
    s._castEffect(h,A,0,0,fraction,null,true);
    const f=s.fogs[0],steps=[];
    for(const [now,delta] of [[10.1,.25],[10.2,2.5],[10+A.dur-.001,.25],[10+A.dur,.25]]) {
      s.t=now;s._tickFogs(delta);
      steps.push({now,delta,damage:hits.splice(0),fields:s.fogs.length,buildup:structuredClone(enemy._elemBuildup||{}),
        poison:enemy._psnStacks||0,bleed:enemy.bleed?{dps:enemy.bleed.dps,until:enemy.bleed.until,pen:enemy.bleed.pen,peer:enemy.bleed.pid}:null});
    }
    fieldFog.push({character,level,fraction,outside,radius:f.r,duration:f.dur,until:f.until,steps});
  }
  const fieldVisibility=[];
  for(const centers of [[],[0],[0,12],[12,0]])for(const targetX of [-1,0,5,10,12,20,80])for(const observerX of [-10,0,5,10,12,20,80])for(const expired of [false,true]) {
    const observer={id:1,kind:'soldier',side:'SWARM',x:observerX,z:0,y:0,hp:100},target=actor(2,'m04','STEEL',targetX,0);
    const s=context([target]);s.ents.set(1,observer);
    s.fogs=centers.map(x=>({x,z:0,r:10,side:'STEEL',until:expired?10:20}));
    s._losBlocked=()=>false;
    const sources=s._visionSources('SWARM');
    fieldVisibility.push({fogs:s.fogs.map(f=>({center:[f.x,-f.z],radius:f.r,until:f.until,side:f.side})),
      target:[targetX,0],observer:[observerX,0],factor:sources[0][2]/d.UNITS.soldier.sight,result:s._visibleTo(target,'SWARM',sources)});
  }
  const fieldBarriers=[];
  const s=context([]);
  for(const angle of [0,.6,Math.PI/2,Math.PI])for(const hp of [0,100])for(const y of [-.01,0,3,6,6.01])for(const endpoint of [false,true]) {
    const slab={x:0,z:0,ang:angle,h:6,hp};s.cubicSlabs=[{slabs:[slab]}];
    const start=[Math.fround(-10*Math.cos(angle)),y,Math.fround(-10*Math.sin(angle))];
    const end=endpoint?[0,y,0]:[-start[0],y,-start[2]];
    fieldBarriers.push({slabs:[{center:[0,0],angle,height:6,hp}],start:[start[0],y,-start[2]],end:[end[0],y,-end[2]],
      result:s._skillBarriersBlocked(start[0],start[2],start[1],end[0],end[2],end[1])});
  }
  const THREE=await import(pathToFileURL(join(source,'out/forest_review/three.module.js')).href);
  const vfx=(await readFile(join(source,'public/js/vfx.js'),'utf8')).replace(/\r\n/g,'\n');
  const begin=vfx.indexOf('export function spawnFogVFX('),end=vfx.indexOf('\n}\n',begin);
  if(begin<0||end<0)throw new Error('Source fog presentation seam missing');
  const spawnFog=new Function('THREE',vfx.slice(begin,end+3).replace('export function','return function'))(THREE);
  const fieldFogGeometry=[];
  for(const radius of [10,35,60])for(const ally of [false,true]) {
    const scene=new THREE.Scene(),effects=[];
    spawnFog(scene,effects,{x:0,z:0,r:radius,dur:8,isAlly:ally});
    const root=effects[0].obj;root.updateMatrixWorld(true);
    const nodes=root.children.map(node=>{
      const positions=node.geometry.getAttribute('position'),indices=node.geometry.index;
      const count=indices?indices.count:positions.count,vertices=[];
      for(let i=0;i<count;i++) {
        const index=indices?indices.getX(i):i;
        vertices.push(new THREE.Vector3().fromBufferAttribute(positions,index).applyMatrix4(node.matrix).toArray());
      }
      return {vertices,opacity:node.material.opacity,color:node.material.color.getHex()};
    });
    const frames=[];
    for(const dt of [.1,5,1.5,1.3]) {
      const age=(frames.at(-1)?.age||0)+dt;
      effects[0].fade(root,(8-age)/8,dt);
      frames.push({age,rotation:root.rotation.y,opacity:root.children[0].material.opacity});
    }
    fieldFogGeometry.push({radius,ally,nodes,frames});
  }
  return {fieldCube,fieldFog,fieldVisibility,fieldBarriers,fieldFogGeometry};
}
