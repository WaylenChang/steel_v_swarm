export async function captureHeadMarks(page, methods, factories, textureCodec, samplerCodec) {
  return page.evaluate(async ({methods,factories,textureCodec,samplerCodec})=>{
    const THREE=await import('three'),d=await import('/js/data.js');
    const {finishTex}=await import('/js/tex.js');
    const capture=new Function('return ('+textureCodec+');')();
    const describe=new Function('return ('+samplerCodec+');')();
    const textures=new Function('THREE','SIDES','sideInfo','finishTex',
      'const _markTex=new Map(),_allyTex=new Map();\n'+factories+'\nreturn {enemy:factionMarkTex,ally:allyMarkTex};')(
      THREE,d.SIDES,d.sideInfo,finishTex);
    const Client=new Function('THREE','factionMarkTex','allyMarkTex','return class {\n'+Object.values(methods).join('\n')+'\n};')(
      THREE,textures.enemy,textures.ally);
    const rules={},images=[],specs={},cases=[];
    const take=(pattern,text,label)=>{
      const result=pattern.exec(text);if(!result)throw new Error('Missing original head mark seam: '+label);
      return result.slice(1).map(Number);
    };
    for(const [kind,method]of Object.entries({enemy:'_enemyMark',ally:'_allyMark',civilian:'_civMark'})) {
      const text=methods[kind];
      const [minimum]=take(/Math.max\(([\d.]+), ent.dimH \?\?/,text,kind+' minimum');
      const [sizeMin,sizeFactor]=take(/sp.scale.setScalar\(Math.max\(([\d.]+), h \* ([\d.]+)\)\)/,text,kind+' scale');
      const [margin,half]=take(/= \(ent.dimTop \?\? h\) \+ ([\d.]+) \+ sp.scale.y \* ([\d.]+)/,text,kind+' anchor');
      const [order]=take(/sp.renderOrder = (\d+)/,text,kind+' order');
      const [fade]=take(/m.opacity \+ dt \* ([\d.]+)/,text,kind+' fade');
      const [frequency]=take(/Math.sin\(now \* ([\d.]+)/,text,kind+' frequency');
      const [amplitude]=take(/\) \* ([\d.]+);/,text.slice(text.lastIndexOf('Math.sin')),kind+' amplitude');
      const phase=/Math.sin\(now \* [\d.]+ \+ ([\d.]+)\)/.exec(text);
      rules[kind]={minimum,sizeMin,sizeFactor,margin,half,order,fade,frequency,amplitude,phase:phase?Number(phase[1]):0};
      for(const side of [...Object.keys(d.SIDES),...Object.keys(d.THIRD.SIDES),d.SUPER_SIDE]) {
        const key=(kind==='ally'?'ally:':'enemy:')+side;
        if(!specs[key]) {
          const texture=(kind==='ally'?textures.ally:textures.enemy)(side);
          specs[key]={...describe(texture,THREE),image:images.length};
          images.push(capture(texture));
        }
      }
      for(const height of [0,1.8,2,8,50])for(const top of [null,0,height+3])for(const following of [false,true]) {
        const client=new Client(),mesh=new THREE.Group();
        mesh.add(new THREE.Mesh(new THREE.BoxGeometry(2,height||1,2),new THREE.MeshBasicMaterial()));
        const ent={mesh,side:'STEEL',cs:'STEEL',fo:following,dimH:height,dimTop:top};
        const frames=[];
        for(const [dt,now,follow]of [[0,0,following],[.016,.016,following],[.5,.516,following],[0,1.1,!following],[.1,2.5,!following]]) {
          ent.fo=follow;client[method](ent,dt,now);
          const sprite=ent[kind==='enemy'?'mark':kind==='ally'?'allyMark':'civMark'];
          frames.push({dt,now,following:follow,size:sprite.scale.x,y:sprite.position.y,opacity:sprite.material.opacity,
            depthTest:sprite.material.depthTest,depthWrite:sprite.material.depthWrite,order:sprite.renderOrder});
        }
        cases.push({kind,height,top,following,frames});
      }
      const client=new Client(),ent={mesh:new THREE.Group(),side:'STEEL',cs:'STEEL',fo:false,dimH:3,dimTop:3};
      client[method](ent,10,0);
      const sprite=ent[kind==='enemy'?'mark':kind==='ally'?'allyMark':'civMark'];
      rules[kind].opacity=sprite.material.opacity;
      if(kind==='civilian') {ent.fo=true;client[method](ent,10,0);rules[kind].followOpacity=sprite.material.opacity;}
    }
    return {rules,images,textures:specs,cases};
  },{methods,factories,textureCodec,samplerCodec});
}
