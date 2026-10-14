// Execute the original presentation queue, including its backward due-callback traversal.
export function burstReferences(d, gameSource) {
  const text = gameSource.replace(/\r\n/g, '\n');
  const performance = { now: () => clock * 1000 };
  let clock = 0;
  const method = name => {
    const start = text.indexOf(`\n  ${name}(`), end = text.indexOf('\n  }\n', start);
    if (start < 0 || end < 0) throw new Error(`Missing source burst method: ${name}`);
    return new Function('fireBurstN', 'fireBurstGap', 'performance',
      `return function ${text.slice(start + 1, end + 4).trimStart().slice(name.length)}`)(d.fireBurstN, d.fireBurstGap, performance);
  };
  const queue = method('_queueBurst'), tick = method('_tickBurstFx');
  const burstSchedules = [];
  const run = (name, commands) => {
    const ctx = {}, fired = [], steps = [];
    for (const command of commands) {
      clock = command.now;
      for (const shot of command.shots || []) {
        const definition = d.heroWeapon(shot.character, shot.slot, shot.level);
        queue.call(ctx, definition, (index, count) => {
          fired.push({token:shot.token,index,count,now:clock,fail:!!shot.fail});
          if (shot.fail) throw new Error('Fixture callback failure');
        });
      }
      tick.call(ctx, clock);
      steps.push({...command,fired:fired.splice(0),pending:(ctx._burstQ || []).map(item => ({at:item.at,index:item.i,count:item.n}))});
    }
    burstSchedules.push({name,steps});
  };
  for (const character of Object.keys(d.CHARACTERS)) for (const slot of ['light','heavy']) for (let level=1;level<=4;level++) {
    const definition = d.heroWeapon(character,slot,level), gap = d.fireBurstGap(definition), count = d.fireBurstN(definition);
    const shot = {character,slot,level,token:`${character}/${slot}/${level}`};
    const commands = [{now:10,shots:[shot]}];
    for (let index=1;index<count;index++) {
      const deadline=10+gap*index;
      const boundary = {token:shot.token,index,at:10,gap};
      commands.push({now:deadline-1e-8,boundary,offset:-1e-8},{now:deadline,boundary,offset:0},{now:deadline,boundary,offset:0});
    }
    commands.push({now:11});
    run(shot.token,commands);
    run(shot.token+'/hitch',[{now:10,shots:[shot]},{now:11},{now:11}]);
  }
  const burstHeroes = Object.keys(d.CHARACTERS).filter(character => d.fireBurstN(d.heroWeapon(character,'light',1))>1);
  if (!burstHeroes.length) throw new Error('Source burst fixtures require high-rate weapons');
  const first=burstHeroes[0], second=burstHeroes.at(-1);
  run('mixed-batches-and-callback-failure',[
    {now:20,shots:[{character:first,slot:'light',level:1,token:'old'}, {character:second,slot:'light',level:4,token:'new',fail:true}]},
    {now:20.01,shots:[{character:first,slot:'light',level:4,token:'changed-tier'}]},
    {now:21},{now:21},{now:22},
  ]);
  return {burstSchedules};
}
