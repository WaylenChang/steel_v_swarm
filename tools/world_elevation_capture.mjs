// Offline frames follow selected source configurations, never the largest map.
export function worldElevationFrames(map, bundles, {battleRect, mapSourceCenter}) {
  const sizes = [...new Set([...bundles.values()]
    .filter(bundle => bundle.map.id === map.id).map(bundle => bundle.size))].sort((a,b)=>a-b);
  return sizes.map(size => {
    const config = map.variants[String(size)]?.config;
    if (!config) throw new Error('Missing selected elevation configuration: '+map.id+'/'+size);
    return {size, config, rect:battleRect(config), center:mapSourceCenter(config,'elevation')};
  });
}

export function captureWorldElevation({rect, center}, grid, xzToLL, sample) {
  if (!Number.isSafeInteger(grid) || grid < 2)
    throw new Error('Invalid source elevation grid');
  const raw = new Float32Array(grid * grid);
  for (let i = 0; i < grid; i++) {
    const z = rect.minZ + (rect.maxZ - rect.minZ) * i / (grid - 1);
    for (let j = 0; j < grid; j++) {
      const x = rect.minX + (rect.maxX - rect.minX) * j / (grid - 1);
      const [lat, lng] = xzToLL(x, z, center);
      const value = sample(lat, lng);
      if (!Number.isFinite(value)) throw new Error('Incomplete source elevation at '+i+'/'+j);
      raw[i * grid + j] = value;
    }
  }
  return raw;
}
