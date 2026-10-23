class_name AudioRules
extends RefCounted

var rules: Dictionary = {}

func configure(metadata: Dictionary) -> void:
	rules = metadata

func fire_id(definition: Variant, slot: String, side: String) -> String:
	var light := "fire_light_energy" if side == "SWARM" else "fire_light_ballistic"
	if definition == null:
		return light
	if not definition is Dictionary:
		push_error("Audio fire routing requires a resolved weapon definition")
		return ""
	if slot != "heavy":
		return "fire_shotgun" if definition.get("fan", false) else light
	match CombatMath.trajectory_class(definition):
		"lob": return "fire_lob"
		"guide": return "fire_missile"
		"fnf": return "fire_fnf"
		"line":
			return "fire_beam" if definition.get("type") == "beam" else "fire_rail" if definition.get("type") == "rail" else "fire_gun"
	return "fire_shotgun" if definition.get("fan", false) else "fire_heavy_generic"

func spatial(camera: Variant, x: float, z: float, y: Variant = null) -> Variant:
	if camera == null:
		return {"gain": rules.defaultGain, "pan": 0.0}
	var transform: Transform3D = camera
	var delta := Vector3(x, transform.origin.y if y == null else float(y), z) - transform.origin
	var distance := delta.length()
	if distance > float(rules.maxDistance):
		return null
	var gain := clampf(float(rules.referenceDistance) / (float(rules.referenceDistance) + distance), rules.minimumGain, 1)
	var horizontal := Vector2(delta.x, delta.z).length()
	if horizontal == 0:
		horizontal = 1
	var pan := clampf((transform.basis.x.x * delta.x + transform.basis.x.z * delta.z) / horizontal, -1, 1)
	return {"gain": gain, "pan": pan}

func event_plan(event: Dictionary, camera: Variant, own_id: Variant) -> Array:
	var positioned := event.get("x") != null and event.get("z") != null
	var position: Variant = spatial(camera, event.x, -float(event.z), event.get("y")) if positioned else {"gain": rules.defaultGain, "pan": 0.0}
	if positioned and position == null:
		return []
	var id := ""
	match event.e:
		"shot":
			if event.get("pid") == own_id:
				return []
			id = "fire_heavy_generic" if event.get("slot") == "heavy" else "fire_light_energy" if event.get("side") == "SWARM" else "fire_light_ballistic"
		"plasma":
			if event.get("pid") == own_id:
				return []
			id = "fire_beam" if event.get("slot") == "heavy" else "fire_shotgun"
		"die":
			if event.get("kind") == "civilian":
				return []
			id = "explosion" if event.get("kind") in ["tower", "base", "tank", "heli", "bunker"] else "explosion_small"
		"boom":
			id = "explosion_small"
			var radius := float(event.get("r", 0)) if event.get("r") != null else 0.0
			if radius == 0:
				radius = float(rules.boom.fallbackRadius)
			position.gain *= clampf(radius / float(rules.boom.divisor), rules.boom.minimum, rules.boom.maximum)
		"cast": id = "cast_ult" if event.get("slot") == "ult" else "cast_skill"
		"crit", "buy":
			if event.get("pid") != own_id:
				return []
			id = "crit" if event.e == "crit" else "ui_buy"
			position = {"gain": rules.eventGains[event.e], "pan": 0.0}
		"sam":
			id = "missile_launch"
			if event.get("from") != null:
				position = spatial(camera, event.from[0], -float(event.from[1]), 2)
				if position == null:
					return []
		"airfall":
			id = "supply"
			position = {"gain": rules.eventGains.airfall, "pan": 0.0}
		"airdrop": id = "supply"
		"relay":
			id = "ui_alert"
			position = {"gain": rules.eventGains.relay, "pan": 0.0}
		"lock":
			if event.get("tpid") != own_id:
				return []
			id = "ui_alert"
			position = {"gain": rules.eventGains.lock, "pan": 0.0}
		_: return []
	return [{"id": id, "gain": position.gain, "pan": position.pan}]

func ambience_mix(query: Dictionary) -> Variant:
	for bed: Dictionary in rules.ambience:
		var value: Variant = query.get(bed.id)
		var number := INF if value == null else VisualPreferences._number(value)
		if is_nan(number):
			continue
		var gain := clampf((float(bed.r) - number) / float(bed.m), 0, 1)
		if gain > 0:
			return {"id": bed.id, "g": gain}
	return null

func music_url(name: String, low: bool) -> Variant:
	if not rules.music.has(name):
		return null
	var entry: Dictionary = rules.music[name]
	return entry.low if low and not str(entry.get("low", "")).is_empty() else entry.hi
