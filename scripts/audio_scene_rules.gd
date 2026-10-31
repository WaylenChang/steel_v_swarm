class_name AudioSceneRules
extends RefCounted

# Source presentation coordinates, matching imported native world geometry.

var rules: Dictionary = {}
var characters: Dictionary = {}
var density_cache: Dictionary = {}

func configure(metadata: Dictionary, roster: Dictionary) -> void:
	rules = metadata.scene
	characters = roster
	density_cache.clear()

func move_category(entity: Dictionary) -> String:
	match entity.get("kind", ""):
		"heli": return "rotor"
		"tank": return "engine"
		"drone": return "wingflap"
		"soldier": return ""
	if ControlPreferences.truthy(entity.get("civ")):
		return ""
	if ControlPreferences.truthy(entity.get("hero")) and ControlPreferences.truthy(entity.get("ch")):
		var motion: Variant = entity.get("loco")
		var weights: Variant = motion.get("w") if motion is Dictionary else null
		var air := float(weights.get("air", 0)) if weights is Dictionary else 0.0
		if ControlPreferences.truthy(entity.get("flies")) or air > float(rules.airThreshold):
			var flight: String = characters.get(entity.ch, {}).get("visual", {}).get("flight", "")
			if flight in ["heli", "tilt"]:
				return "rotor"
			return "engine" if flight in ["jet", "uav"] else "wingflap"
		return "stomp"
	return ""

func movement(entities: Array, camera: Transform3D, own_weights: Variant, ground_query: Callable, own_ground: int = 0, self_bed: bool = false, low_power: bool = false) -> Array[Dictionary]:
	if low_power:
		return []
	var best := {}
	var counts := {}
	for category: String in rules.categories:
		best[category] = null
		counts[category] = 0
	for entity: Dictionary in entities:
		var self_source := ControlPreferences.truthy(entity.get("isSelf"))
		if self_source and not self_bed or ControlPreferences.truthy(entity.get("isStatic")) or ControlPreferences.truthy(entity.get("dead")) or not entity.mesh.visible:
			continue
		var category := move_category(entity)
		if category.is_empty() or self_source and category not in ["stomp", "engine"]:
			continue
		var position := _position(entity)
		var dx := float(position.x) - float(camera.origin.x)
		var dz := float(position.z) - float(camera.origin.z)
		var dy := float(position.y) - float(camera.origin.y)
		# The source uses this double sum, not a Float32 vector length or hypot3.
		var distance := 0.0 if self_source else sqrt(dx * dx + dz * dz + dy * dy)
		if distance > float(rules.maxDistance):
			continue
		counts[category] += 1
		if best[category] == null or distance < float(best[category].distance):
			var motion: Variant = entity.get("loco")
			var weights: Variant = own_weights if self_source else motion.get("w") if motion is Dictionary else null
			best[category] = {"distance": distance, "dx": 0.0 if self_source else dx, "dz": 0.0 if self_source else dz,
				"weights": weights, "self": self_source, "x": float(position.x), "z": float(position.z)}
	var result: Array[Dictionary] = []
	for category: String in rules.categories:
		var selected: Variant = best[category]
		if selected == null:
			result.append({"category": category, "gain": 0.0, "pan": 0.0, "rate": 1.0, "wet": 0.0})
			continue
		var weights: Variant = selected.weights
		var moving := clampf(float(weights.get("walk", NAN)) + float(weights.get("run", NAN)), 0, 1) if weights is Dictionary else 0.0
		var running := clampf(float(weights.get("run", NAN)), 0, 1) if weights is Dictionary else 0.0
		var distance := float(rules.referenceDistance) / (float(rules.referenceDistance) + float(selected.distance))
		var density := clampf(float(rules.densityBase) + float(counts[category]) * float(rules.densityStep), rules.densityBase, 1)
		var floor_gain: float = rules.groundFloor if category in ["stomp", "engine"] else rules.airFloor
		var gain := clampf(distance * density * (floor_gain + (1 - floor_gain) * moving), 0, 1)
		var horizontal := CarrierRules.hypot2(float(selected.dx), float(selected.dz))
		if horizontal == 0:
			horizontal = 1
		var pan := clampf((camera.basis.x.x * float(selected.dx) + camera.basis.x.z * float(selected.dz)) / horizontal, -1, 1)
		var wet := 0.0
		if category == "stomp":
			if not selected.self and not ground_query.is_valid():
				push_error("Movement audio requires the existing terrain environment query")
				return []
			var ground := own_ground if selected.self else int(ground_query.call(selected.x, selected.z))
			wet = 1.0 if ground == 1 else 0.0
		result.append({"category": category, "gain": gain, "pan": pan,
			"rate": clampf(float(rules.rateBase) + running * float(rules.rateSlope), rules.rateMinimum, rules.rateMaximum), "wet": wet})
	return result

func density(query: SourceBlockerQuery, point: Vector2) -> Dictionary:
	if query == null:
		return {"bld": 0.0, "tree": 0.0}
	var local_x := float(point.x) / float(rules.cell) - .5
	var local_z := float(point.y) / float(rules.cell) - .5
	var first := Vector2i(floori(local_x), floori(local_z))
	var fx := local_x - first.x
	var fz := local_z - first.y
	var c00 := _cell(query, first)
	var c10 := _cell(query, first + Vector2i.RIGHT)
	var c01 := _cell(query, first + Vector2i.DOWN)
	var c11 := _cell(query, first + Vector2i.ONE)
	var result := {}
	for key: String in ["bld", "tree"]:
		result[key] = (float(c00[key]) * (1 - fx) + float(c10[key]) * fx) * (1 - fz) + (float(c01[key]) * (1 - fx) + float(c11[key]) * fx) * fz
	return result

func _cell(query: SourceBlockerQuery, key: Vector2i) -> Dictionary:
	if density_cache.has(key):
		return density_cache[key]
	var buildings := 0
	var trees := 0
	for index: int in query.grid.get(key, []):
		var entry: Dictionary = query.entries[index]
		if ControlPreferences.truthy(entry.get("bld")):
			buildings += 1
		elif entry.get("cl") == "tree":
			trees += 1
	var result := {"bld": minf(1, float(buildings) / float(rules.urbanFull)), "tree": minf(1, float(trees) / float(rules.forestFull))}
	density_cache[key] = result
	return result

func place(position: Vector2, ground: int, tunnel: bool, densities: Dictionary, entities: Array) -> Dictionary:
	var camp := INF
	for entity: Dictionary in entities:
		if not ControlPreferences.truthy(entity.get("isStatic")) or ControlPreferences.truthy(entity.get("dead")):
			continue
		var location := _position(entity)
		var distance := CarrierRules.hypot2(float(location.x) - float(position.x), float(location.z) - float(position.y))
		if distance < camp:
			camp = distance
	return {"tunnel": 0 if tunnel else 1, "water": 0 if ground == 1 else 1, "swamp": 0 if ground == 2 else 1,
		"camp": camp, "urban": 1 - float(densities.bld), "forest": 1 - float(densities.tree)}

static func _position(entity: Dictionary) -> Dictionary:
	return entity.mesh.position
