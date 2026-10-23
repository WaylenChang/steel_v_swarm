class_name WildlifePopulation
extends RefCounted

static func assemble(base: Dictionary, catalogs: Array, densities: Dictionary) -> Dictionary:
	if int(base.get("budget", 0)) <= 0 or not is_finite(float(base.get("densityLimit", 0))) or float(base.get("densityLimit", 0)) <= 0:
		push_error("Missing original wildlife population budget/density declarations")
		return {}
	var profile: Dictionary = base.duplicate(true)
	profile.states = []
	profile.batches = []
	var routes: Array = catalogs.filter(func(entry): return bool(entry.low) == bool(base.low))
	routes.sort_custom(func(a, b):
		return int(a.catalog.order) < int(b.catalog.order) if int(a.catalog.order) != int(b.catalog.order) else int(a.catalog.routeIndex) < int(b.catalog.routeIndex))
	var population_batches := {}
	var total := 0
	for entry: Dictionary in routes:
		var density := float(densities.get(entry.catalog.preference, 0))
		if not density > 0 or total >= int(base.budget):
			continue
		var count := mini(int(base.budget) - total, maxi(1, int(floor(float(entry.catalog.baseCount) * minf(float(base.densityLimit), density) + 0.5))))
		if count == 0:
			continue
		if entry.states.size() != 1 or entry.batches.size() != 1 or count > int(entry.states[0].count):
			push_error("Missing original wildlife capacity for selected source density")
			return {}
		var state: Dictionary = entry.states[0].duplicate(true)
		state.count = count
		for key: String in ["pos", "vel", "spd", "off", "wing"]:
			state[key] = state[key].slice(0, count * 3 if key in ["pos", "vel"] else count)
		var state_index: int = profile.states.size()
		profile.states.append(state)
		var order := int(entry.catalog.order)
		if not population_batches.has(order):
			var new_batch: Dictionary = entry.batches[0].duplicate(true)
			new_batch.animals = []
			population_batches[order] = profile.batches.size()
			profile.batches.append(new_batch)
		var batch: Dictionary = profile.batches[int(population_batches[order])]
		for index in range(count):
			batch.animals.append({"state": state_index, "i": index})
		total += count
	return profile
