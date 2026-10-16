class_name BloodSplatState
extends RefCounted

var blood: Array[Dictionary] = []
var glints: Array[Dictionary] = []
var sequence := 0
var blood_on := false
var glint_on := false
var visual_random := RandomNumberGenerator.new()
var random_sample := Callable()

func _init() -> void:
	visual_random.randomize()

func spray(event: Dictionary, camera: Transform3D, fov: float, aspect: float, vital: Dictionary) -> bool:
	if vital.get("dead", false) or not ControlPreferences.truthy(vital.get("side")):
		return false
	var pool := float(vital.get("max_hp", 0)) + float(vital.get("max_shield", 0))
	var amount := float(event.amount)
	if not amount > 0 or not pool > 0:
		return false
	var rules: Dictionary = Content.balance.screenSplats.blood
	var portion := amount / (pool * float(rules.REF_F))
	if is_nan(portion):
		return false
	var fraction := minf(1, portion)
	if not fraction > 0:
		return false
	var origin: Vector3 = event.origin
	origin.y = float(event.elevation) if event.has("elevation") else 0.0
	var point := camera.affine_inverse() * origin
	var forward := -float(point.z)
	var bearing := atan2(point.x, forward)
	var elevation := atan2(point.y, Vector2(point.x, forward).length()) if event.has("elevation") else 0.0
	var half_vertical := deg_to_rad(fov) * .5
	var half_horizontal := atan(tan(half_vertical) * (aspect if aspect != 0 else 1.0))
	var position := screen_uv(bearing, elevation, half_horizontal, half_vertical)
	var shielded: bool = vital.get("defending", false) and float(vital.get("shield", 0)) > 0
	var shape: Dictionary = Content.balance.screenSplats.glint if shielded else rules
	var radius := float(shape.DROP_MIN) + (float(shape.DROP_MAX) - float(shape.DROP_MIN)) * fraction
	var count := floori(float(rules.N_MIN) + (float(rules.N_MAX) - float(rules.N_MIN)) * fraction + .5)
	var drops: Array[Dictionary] = [{"x": 0.0, "y": 0.0, "r": radius}]
	for index in range(1, count):
		var angle := _random() * TAU
		var distance := sqrt(_random()) * float(rules.SPREAD) * (.35 + .65 * fraction)
		drops.append({"x": cos(angle) * distance, "y": sin(angle) * distance, "r": radius * (.18 + .42 * _random())})
	sequence += 1
	var entry := {"id": sequence, "u": position.x, "v": position.y, "drops": drops, "left": float(shape.HOLD_S) + float(shape.FADE_S)}
	var list: Array[Dictionary] = glints if shielded else blood
	list.append(entry)
	while list.size() > int(shape.MAX):
		list.pop_front()
	return true

static func screen_uv(bearing: float, elevation: float, half_horizontal: float, half_vertical: float) -> Vector2:
	bearing = 0.0 if is_nan(bearing) else bearing
	elevation = 0.0 if is_nan(elevation) else elevation
	var edge: float = Content.balance.screenSplats.blood.EDGE
	var horizontal := .5 + .5 * clampf(bearing / half_horizontal if half_horizontal > 0 else 0.0, -1, 1)
	var vertical := .5 - .5 * clampf(elevation / half_vertical if half_vertical > 0 else 0.0, -1, 1)
	return Vector2(edge + horizontal * (1 - 2 * edge), edge + vertical * (1 - 2 * edge))

static func alpha(left: float, glint: bool = false) -> float:
	var rules: Dictionary = Content.balance.screenSplats.glint if glint else Content.balance.screenSplats.blood
	var remaining := clampf(0 if is_nan(left) else left, 0, float(rules.HOLD_S) + float(rules.FADE_S))
	if remaining >= float(rules.FADE_S):
		return float(rules.PEAK)
	var fraction := remaining / float(rules.FADE_S)
	return float(rules.PEAK) * fraction * fraction * (3 - 2 * fraction)

func advance(delta: float) -> Dictionary:
	var updates := {"blood": null, "glint": null}
	for key: String in ["blood", "glint"]:
		var list: Array[Dictionary] = glints if key == "glint" else blood
		var was_on := glint_on if key == "glint" else blood_on
		if list.is_empty():
			if was_on:
				updates[key] = []
				if key == "glint":
					glint_on = false
				else:
					blood_on = false
			continue
		for entry: Dictionary in list:
			entry.left -= delta
		for index in range(list.size() - 1, -1, -1):
			if float(list[index].left) <= 0:
				list.remove_at(index)
		if key == "glint":
			glint_on = true
		else:
			blood_on = true
		updates[key] = list.map(func(entry): return {"id": entry.id, "u": entry.u, "v": entry.v, "drops": entry.drops,
			"a": alpha(float(entry.left), key == "glint")})
	return updates

func clear() -> Dictionary:
	blood.clear()
	glints.clear()
	blood_on = false
	glint_on = false
	return {"blood": [], "glint": []}

func _random() -> float:
	return float(random_sample.call()) if random_sample.is_valid() else float(visual_random.randi()) / 4294967296.0
