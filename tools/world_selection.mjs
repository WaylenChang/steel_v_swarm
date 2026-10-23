// Offline selection only; every returned bundle belongs to the source catalog.
export function selectWorldBundles(catalog, seasons, arguments_ = []) {
  const maps = arguments_.filter(value => !value.startsWith('--'));
  const requested = arguments_.filter(value => value.startsWith('--bundle=')).map(value => value.slice(9));
  for (const value of arguments_) {
    if (value.startsWith('--') && value !== '--reuse' && value !== '--list-bundles' && !value.startsWith('--bundle='))
      throw new Error('Unknown world capture argument: ' + value);
  }
  for (const id of maps) {
    if (!catalog.some(map => map.id === id || map.source_id === id || map.swapped_variants && map.id + '_swap' === id))
      throw new Error('Unknown original map ID: ' + id);
  }
  const result = new Map();
  for (const entry of catalog) {
    const layouts = entry.swapped_variants
      ? [entry, {...entry, id: entry.id + '_swap', source_id: entry.id, variants: entry.swapped_variants}]
      : [entry];
    for (const map of layouts) {
      if (maps.length && !maps.includes(map.id) && !maps.includes(map.source_id) && !maps.includes(entry.id) && !maps.includes(entry.source_id)) continue;
      for (const size of Object.keys(map.variants).map(Number).sort((a, b) => a - b)) {
        const selectedSeasons = map.chapter ? [map.variants[String(size)].config.env?.season || 'summer'] : seasons;
        for (const season of selectedSeasons) {
          if (!seasons.includes(season)) throw new Error('Unsupported original map season: ' + map.id);
          const name = `${map.id}_${size}_${season}`;
          if (result.has(name)) throw new Error('Duplicate original world bundle: ' + name);
          result.set(name, {map, size, season});
        }
      }
    }
  }
  if (!result.size) throw new Error('No matching original world bundles');
  if (!requested.length) return result;
  for (const name of requested) {
    if (!result.has(name)) throw new Error('Unknown or conflicting original world bundle: ' + name);
  }
  const names = new Set(requested);
  return new Map([...result].filter(([name]) => names.has(name)));
}
