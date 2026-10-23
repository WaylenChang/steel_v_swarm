export function captureTrainBundle(group) {
  const trains = [];
  group.updateMatrixWorld(true);
  group.traverse(node => {
    const source = node.userData.nativeTrain;
    if (!source) return;
    if (!Array.isArray(source.points) || source.points.length < 2 || !(source.total > 0)
      || ![source.total,source.start,source.speed,source.lookahead,source.turnSquared,source.parallelPerturbation].every(Number.isFinite))
      throw new Error('Invalid original train motion capture');
    if (source.points.some(point=>point.length !== 3 || !point.every(Number.isFinite)))
      throw new Error('Invalid original train path');
    if (source.start < 0 || source.start > source.total || !node.matrixWorld.elements.every(Number.isFinite))
      throw new Error('Invalid original train phase/bind pose');
    const id = trains.length + 1;
    node.userData.nativeTrainId = id;
    trains.push({...source,id,initialFrame:node.matrixWorld.toArray()});
  });
  return {trainsCaptured:true,trains};
}
