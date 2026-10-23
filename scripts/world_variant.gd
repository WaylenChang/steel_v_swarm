class_name WorldVariant
extends RefCounted

static func identity(base: String, environment: Dictionary) -> Dictionary:
	var name_parts := base.get_file().get_basename().rsplit("_", true, 1)
	var season: Variant = environment.get("season")
	if not ControlPreferences.truthy(season):
		season = "summer"
	if not season is String or not Content.constants.ENV.seasons.has(season):
		return {}
	if not base.ends_with(".res") or name_parts.size() != 2 or name_parts[0].is_empty() or not name_parts[1].is_valid_int():
		return {}
	var size := int(name_parts[1])
	if size <= 0:
		return {}
	return {"map": name_parts[0], "teamSize": size, "season": season}

static func path(base: String, environment: Dictionary) -> String:
	var selected := identity(base, environment)
	return base.get_basename() + "_" + selected.season + ".res" if not selected.is_empty() else ""

static func matches_identity(captured: Variant, expected: Dictionary) -> bool:
	if not captured is Dictionary or captured.size() != 3 or expected.size() != 3:
		return false
	var size: Variant = captured.get("teamSize")
	if not (size is int or size is float) or not is_finite(float(size)):
		return false
	# Godot JSON numbers are floats; dictionary equality distinguishes them from ints.
	return captured.get("map") == expected.map and captured.get("season") == expected.season and float(size) == float(expected.teamSize)

static func select_required(arguments: Array = []) -> Dictionary:
	var maps := arguments.filter(func(value): return not str(value).begins_with("--bundle="))
	var bundles := arguments.filter(func(value): return str(value).begins_with("--bundle="))
	for map: String in maps:
		if required([map]).is_empty():
			return {"worlds": {}, "error": "Unknown original map ID: " + map}
	var manifest := required(maps)
	if manifest.is_empty():
		return {"worlds": {}, "error": "No matching original seasonal world requirements"}
	if bundles.is_empty():
		return {"worlds": manifest, "error": ""}
	var selected := {}
	for argument: String in bundles:
		var target := "res://assets/worlds/" + argument.trim_prefix("--bundle=") + ".res"
		if not manifest.has(target):
			return {"worlds": {}, "error": "Unknown original seasonal world bundle: " + argument}
		selected[target] = manifest[target]
	return {"worlds": selected, "error": ""}

static func required(selected_maps: Array = []) -> Dictionary:
	var result := {}
	for entry: Dictionary in Content.maps + Content.campaign.get("maps", []):
		var layouts: Array = [entry]
		if entry.has("swapped_variants"):
			var swapped := entry.duplicate()
			swapped.id = str(entry.id) + "_swap"
			swapped.variants = entry.swapped_variants
			layouts.append(swapped)
		for layout: Dictionary in layouts:
			if not selected_maps.is_empty() and not selected_maps.has(entry.id) and not selected_maps.has(entry.get("source_id", "")) and not selected_maps.has(layout.id):
				continue
			if not _add_layout(result, layout):
				return {}
	return result

static func _add_layout(result: Dictionary, entry: Dictionary) -> bool:
	for size: String in entry.variants:
		var seasons: Array = Content.constants.ENV.seasons.keys()
		if entry.has("chapter"):
			var authored_environment: Dictionary = entry.variants[size].config.get("env", {})
			seasons = [authored_environment.season if ControlPreferences.truthy(authored_environment.get("season")) else "summer"]
		var base := "res://assets/worlds/%s_%d.res" % [entry.id, int(size)]
		for season: String in seasons:
			var environment := {"season": season}
			var target := path(base, environment)
			if target.is_empty():
				push_error("Unsupported original world season: " + str(season))
				return false
			result[target] = identity(base, environment)
	return true
