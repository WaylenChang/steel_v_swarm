class_name CombatEffects
extends Node3D

signal blast_requested(point: Vector3, radius: float)

var effects: Array[Dictionary] = []
var free_nodes: Dictionary = {}
var geometries: Dictionary = {}
var free_authored := 0
var visual_random := RandomNumberGenerator.new()
var low_power := false
var random_sample := Callable()

static func available() -> bool:
	var rules: Dictionary = Content.balance.get("npcShots", {})
	if rules.is_empty() or not ResourceLoader.exists("res://assets/ui/shot-spark.png"):
		return false
	if not Content.balance.has("destruction") or not Content.balance.destruction.has("sceneProfiles") or not Content.balance.destruction.has("damageThresholds"):
		return false
	if not DamageFx.available():
		return false
	if not MissilePresentation.available():
		return false
	if not Content.balance.destruction.has("removal"):
		return false
	if not DissolveBinding.available():
		return false
	for keys: Array in Content.balance.destruction.comicKeys.values():
		for key: String in keys:
			if not ResourceLoader.exists("res://assets/ui/combat-%s.png" % key):
				return false
	for index in range(Content.balance.destruction.palette.size()):
		if not ResourceLoader.exists("res://assets/npc_effects/chunk%d.scn" % index):
			return false
	for key: String in ["fire", "smoke"]:
		if not ResourceLoader.exists("res://assets/ui/combat-%s.png" % key):
			return false
	for key: String in ["beam6", "beam10", "shock", "beam_ring", "bead", "ion_throat"]:
		if not rules.get("shapes", {}).has(key) or not ResourceLoader.exists("res://assets/npc_effects/%s.scn" % key):
			return false
	var colors: Array = rules.colors.values().map(func(value): return int(value.col))
	for style: Dictionary in rules.byWid.values():
		if style.has("color"):
			colors.append(int(style.color))
	for color: int in colors:
		for type: String in ["shell", "rocket"]:
			var key := "npc-%s-%06x" % [type, color]
			if not Content.balance.get("projectileVisual", {}).get("profiles", {}).has(key) or not ResourceLoader.exists("res://assets/projectiles/%s.scn" % key):
				return false
	return true

func _init() -> void:
	visual_random.randomize()

func _ready() -> void:
	for key: String in Content.balance.npcShots.limits.prewarm:
		var nodes: Array[Node3D] = []
		for index in range(int(Content.balance.npcShots.limits.prewarm[key])):
			nodes.append(_take(key))
		for node: Node3D in nodes:
			_drop({"key": key, "obj": node})

func crowded() -> bool:
	var rules: Dictionary = Content.balance.npcShots.limits
	return effects.size() >= int(rules.low if low_power else rules.normal)

func npc(origin: Vector3, target: Vector3, kind: String, wid: Variant, side: String, collision: Callable,
		velocity: Variant = null, gravity: float = 0, flight: float = 0) -> Dictionary:
	if crowded():
		return {}
	var style := NpcShotMotion.style(kind, wid)
	var colors: Dictionary = Content.balance.npcShots.colors.get(side, Content.balance.npcShots.colors[""])
	var color := int(style.get("color", colors.col))
	# The source artillery entry omits core, retaining unitShotFx's white default.
	var core := 0xffffff if style.mode == "shell" else int(colors.hot)
	var size := float(style.size)
	spark(origin, size, core)
	if style.mode == "launch":
		shock(origin, size * .8, color)
		return {"style": style}
	var plan := NpcShotMotion.prepare(kind, wid, origin, target, collision, velocity, gravity, flight)
	if plan.skip:
		return plan
	if style.mode == "beam":
		energy_beam(origin, plan.target, color, size * .15, .22, 2, core)
	elif style.mode in ["gun", "cannon"]:
		var heavy: bool = style.mode == "cannon"
		beam(origin, plan.target, color, .16 if heavy else .09, size * .07)
		if heavy:
			beam(origin, plan.target, core, .075, size * .025)
		spark(plan.target, size, core)
	else:
		var key := "npc-%s-%06x" % ["shell" if style.mode == "shell" else "rocket", color]
		var model := _take_projectile(key)
		model.scale = Vector3.ONE * size
		model.position = origin
		model.quaternion = plan.quaternion
		model.step_fx(0, 0)
		spark(plan.target, size, core, plan.ttl)
		_push({"type": "projectile", "key": key, "obj": model, "plan": plan}, plan.ttl)
	return plan

func impact(point: Vector3, radius: float, color: int, core: int, heavy: bool = false) -> void:
	spark(point, radius * (.72 if heavy else 1.0), core)
	if not heavy:
		return
	spark(point, radius, color)
	shock(point, radius, color)

func muzzle(point: Vector3, heavy: bool, side: String) -> void:
	var colors: Dictionary = Content.balance.npcShots.colors.get(side, Content.balance.npcShots.colors[""])
	impact(point, 2.6 if heavy else 1.3, int(colors.col), int(colors.hot), heavy)

func shot(origin: Vector3, target: Vector3, heavy: bool, side: String, contact: bool = false) -> void:
	var colors: Dictionary = Content.balance.npcShots.colors.get(side, Content.balance.npcShots.colors[""])
	muzzle(origin, heavy, side)
	beam(origin, target, int(colors.col), .30 if heavy else .13, .30 if heavy else .075)
	if heavy:
		beam(origin, target, int(colors.hot), .18, .11)
	if contact:
		impact(target, 4.2 if heavy else 1.6, int(colors.col), int(colors.hot), heavy)

func explosion(point: Vector3, radius: float, color: int) -> void:
	if crowded():
		return
	impact(point, radius, color, 0xfff3d0, true)
	var node := _take("bead") as MultiMeshInstance3D
	node.position = point
	node.basis = Basis.IDENTITY
	node.multimesh.instance_count = 10 if low_power else 18
	_push({"type": "debris", "key": "bead", "obj": node, "radius": radius, "color": color}, .65)

func death(event: Dictionary, ground: float) -> void:
	for command: Dictionary in DeathPresentation.commands(event.kind, event.get("side", ""), event.position, ground):
		match command.type:
			"explosion": explosion(command.point, float(command.radius), int(command.color))
			"blast": blast_requested.emit(command.point, float(command.radius))
			"mechanical": mechanical_debris(command.point, command.big, command.accent)
			"comic": comic(command.point, command.big, command.hue)

func mechanical_debris(point: Vector3, big: bool = false, accent: Variant = null) -> void:
	_mechanical_debris(point, big, accent, _sample_random)

func _mechanical_debris(point: Vector3, big: bool, accent: Variant, sample: Callable) -> void:
	if crowded():
		return
	if not free_nodes.has("mechanical"):
		free_nodes["mechanical"] = []
	var node: MechanicalDebris
	if free_nodes.mechanical.is_empty():
		node = MechanicalDebris.new()
		add_child(node)
	else:
		node = free_nodes.mechanical.pop_back()
	node.configure(point, big, accent, low_power, sample)
	_push({"type": "mechanical", "key": "mechanical", "obj": node}, 1.4 if big else 1.0)

func retired_body(view: RetiredBody, mobile: bool) -> void:
	_push({"type": "retired_body", "obj": view.model, "view": view, "mobile": mobile, "scale_y": view.model.scale.y},
		float(Content.balance.destruction.removal.duration))

func missile_smoke(point: Vector3) -> void:
	# Original missile puffs bypass admission limits but share global retirement.
	var node := _take("missile_smoke")
	node.position = point
	node.quaternion = Quaternion.IDENTITY
	_tint(node, 0xcfd6da)
	_push({"type": "missile_smoke", "key": "missile_smoke", "obj": node}, .7)

func scene_damage_burst(id: int, kind: String, point: Vector3, height: float, radius: float, stage: int) -> void:
	var profile: Dictionary = Content.balance.destruction.sceneProfiles.get(kind, {})
	if profile.is_empty():
		return
	# Source multiplication uses a JavaScript Number before uint32 conversion.
	var random := SourceRng.new(int(fposmod(float(id) * 2654435761.0 + stage, 4294967296.0)))
	_mechanical_debris(point + Vector3.UP * height * .45, stage >= 2, profile.color, random.next)
	shock(point + Vector3.UP * .2, maxf(2, radius) * (1.4 if stage == 3 else .8), int(profile.color))

func scene_collapse(target: Node3D, id: int, instant: bool = false) -> void:
	var effect := {"type": "collapse", "key": "collapse", "target": weakref(target), "id": id,
		"scale": target.scale, "rotation": target.rotation}
	if instant:
		_pose_collapse(effect, 0)
		return
	var controller := Node3D.new()
	add_child(controller)
	effect.obj = controller
	_push(effect, .7)

func _pose_collapse(effect: Dictionary, remaining: float) -> void:
	var target: Node3D = effect.target.get_ref()
	if target == null:
		return
	var pose := SceneRules.collapse_pose(int(effect.id), effect.scale, effect.rotation, 1 - remaining * remaining)
	target.scale = pose.scale
	target.rotation = pose.rotation

func comic(point: Vector3, big: bool = false, hue: Variant = null) -> void:
	# The source admits comic pops even when ordinary effects are crowded.
	var rules: Dictionary = Content.balance.destruction
	var family := "big" if big else "small"
	var palette := int(hue) if hue != null else (18 if big else 48)
	var keys: Array = rules.comicKeys["%s/%d" % [family, palette]]
	var key: String = keys[floori(_sample_random() * keys.size())]
	var node := _take("comic") as MeshInstance3D
	node.position = point
	node.quaternion = Quaternion.IDENTITY
	node.scale = Vector3.ONE * .01
	node.material_override.set_shader_parameter("spark_texture", load("res://assets/ui/combat-%s.png" % key))
	node.material_override.set_shader_parameter("roll", (_sample_random() - .5) * .5)
	node.material_override.set_shader_parameter("opacity", 1.0)
	_push({"type": "comic", "key": "comic", "obj": node, "size": float(rules.sizes[family])}, float(rules.lifetimes[family]))

func blast_burst(point: Vector3, ground: float, radius: float, kamikaze: bool, sam: bool) -> void:
	explosion(point, radius * .8, 0xff7a2a if kamikaze else 0xff7744 if sam else 0xffaa33)
	if point.y - ground < 12:
		shock(Vector3(point.x, ground, point.z), radius, 0xffb066 if kamikaze else 0xffd27a)
	if kamikaze:
		embers(point + Vector3.UP, 12, 3)

func victim(point: Vector3, height: float, kind: String, shielded: bool, camera: Variant = null) -> void:
	var factor := clampf(camera.distance_to(point) / 60.0, 1, 4) if camera is Vector3 else 1.0
	var at := point + Vector3.UP * (height if ControlPreferences.truthy(height) else 4.0) * .5
	if shielded:
		spark(at, 1.2 * factor, 0xbfdcff)
		return
	if kind in ["tower", "base"]:
		var base := kind == "base"
		spark(at, (9 if base else 7) * factor, 0xfff3d0)
		spark(at, (12 if base else 9) * factor, 0xffb055)
		shock(point, (15 if base else 11) * minf(factor, 2), 0xffc98a)
		embers(at, 16 if base else 12, (8 if base else 6) * factor)
		crash_smoke(at + Vector3.UP, (1.5 if base else 1.2) * minf(factor, 2))
		return
	spark(at, 2.2 * factor, 0xfff3d0)
	spark(at, 2.8 * factor, 0xffb055)
	embers(at, 5, 2 * factor)
	crash_smoke(at + Vector3.UP, .55 * minf(factor, 2))

func embers(point: Vector3, count: int = 8, spread: float = 2) -> void:
	for index in range(count):
		var origin := point + Vector3(_sample_random() - .5, _sample_random() - .5, _sample_random() - .5) * spread
		var size := .35 + _sample_random() * .5
		var color := 0xffd27a if _sample_random() < .5 else 0xff9840
		var sprite := _sprite(true, origin, size, color, .95)
		var velocity := Vector3((_sample_random() - .5) * 6, 4 + _sample_random() * 8, (_sample_random() - .5) * 6)
		_push({"type": "sprite_gravity", "key": "sprite_fire", "obj": sprite, "velocity": velocity, "opacity": .95}, .7 + _sample_random() * .6)

func crash_smoke(point: Vector3, size: float = 1) -> void:
	var base := 3.4 * size
	var origin := point + Vector3((_sample_random() - .5) * 2, 0, (_sample_random() - .5) * 2)
	var sprite := _sprite(false, origin, base, 0x484c50, .6)
	var velocity := Vector3(0, 5 + _sample_random() * 4, 0)
	_push({"type": "sprite_drift", "key": "sprite_smoke", "obj": sprite, "velocity": velocity,
		"base": base, "grow": base * 2.2, "opacity": .6, "delay": 0.0}, 1.1)

func death_plume(point: Vector3) -> void:
	for index in range(40):
		var fire := index < 22
		var angle := _sample_random() * TAU
		var radius := _sample_random() * 3
		var base := 3 + _sample_random() * 2 if fire else 5 + _sample_random() * 3
		var opacity := .95 if fire else .62
		var origin := point + Vector3(cos(angle) * radius, _sample_random() * 2, sin(angle) * radius)
		var color := (0xff8a3a if _sample_random() < .5 else 0xffd166) if fire else 0x4a4e52
		var sprite := _sprite(fire, origin, base, color, opacity)
		var velocity := Vector3((_sample_random() - .5) * 2,
			4 + _sample_random() * 4 if fire else 7 + _sample_random() * 6, (_sample_random() - .5) * 2)
		var delay := 0.0 if fire else _sample_random() * .5
		sprite.visible = delay <= 0
		_push({"type": "sprite_drift", "key": "sprite_fire" if fire else "sprite_smoke", "obj": sprite,
			"velocity": velocity, "base": base, "grow": base * (1.8 if fire else 3.2), "opacity": opacity, "delay": delay}, 2.0)
	embers(point + Vector3.UP, 14, 4)

func engulf(frame: Transform3D) -> void:
	var forward := frame.basis * Vector3.FORWARD
	var right := frame.basis * Vector3.RIGHT
	for index in range(4):
		var side := 1 if index % 2 else -1
		var smoke := index >= 2
		var distance := (1.8 if smoke else 1.6) + _sample_random() * 1.2
		var base := 1.8 + _sample_random() * 1.3 if smoke else 1.1 + _sample_random()
		var lateral := side * ((2.4 if smoke else 1.9) + base * .35 + _sample_random() * 1.2)
		var point := frame.origin + forward * distance + right * lateral
		point.y += (.2 if smoke else -.4) - _sample_random() * .9
		var rise := 2.0 if smoke else 3 + _sample_random() * 3
		var grow := 1.2 if smoke else .8
		var opacity := .55 if smoke else .9
		var color := 0x4a4e52 if smoke else (0xff7a2a if _sample_random() < .5 else 0xffd166)
		var sprite := _sprite(not smoke, point, base, color, opacity)
		var lifetime := (.5 if smoke else .32) + _sample_random() * .26
		_push({"type": "sprite_drift", "key": "sprite_smoke" if smoke else "sprite_fire", "obj": sprite,
			"velocity": Vector3.UP * rise, "base": base, "grow": base * grow, "opacity": opacity, "delay": 0.0}, lifetime)
	for side in [-1, 1]:
		embers(Vector3(frame.origin.x + right.x * side * 2.2, frame.origin.y - .3, frame.origin.z + right.z * side * 2.2), 2, 1.6)

func _sprite(fire: bool, point: Vector3, size: float, color: int, opacity: float) -> MeshInstance3D:
	var sprite := _take("sprite_fire" if fire else "sprite_smoke") as MeshInstance3D
	sprite.position = point
	sprite.quaternion = Quaternion.IDENTITY
	sprite.scale = Vector3.ONE * size
	_tint(sprite, color)
	sprite.material_override.set_shader_parameter("opacity", opacity)
	return sprite

func spark(point: Vector3, radius: float, color: int, delay: float = 0) -> void:
	if crowded():
		return
	var node := _take("spark") as MeshInstance3D
	node.position = point
	node.quaternion = Quaternion.IDENTITY
	node.scale = Vector3.ONE * radius * .4
	_tint(node, color)
	node.material_override.set_shader_parameter("opacity", 1.0)
	node.material_override.set_shader_parameter("roll", _sample_random() * PI)
	_push({"type": "spark", "key": "spark", "obj": node, "radius": radius, "delay": delay}, delay + .15)

func shock(point: Vector3, radius: float, color: int) -> void:
	if crowded():
		return
	var node := _take("shock")
	node.position = point + Vector3.UP * .6
	node.quaternion = Quaternion(Vector3.RIGHT, -PI / 2)
	_tint(node, color)
	_push({"type": "shock", "key": "shock", "obj": node, "radius": radius}, .28)

func beam(origin: Vector3, target: Vector3, color: int, ttl: float = .4, width: float = .08, opacity: float = .85) -> void:
	if crowded() or origin.distance_to(target) < .01:
		return
	var node := _axis("beam6", origin, target, width, color)
	_push({"type": "beam", "key": "beam6", "obj": node, "width": width, "opacity": opacity}, ttl)

func energy_beam(origin: Vector3, target: Vector3, color: int, radius: float, ttl: float, rings: float, core: int, definition: Dictionary = {}) -> void:
	if crowded():
		return
	if authored_discharge(origin, target, definition, "beam", radius, ttl):
		return
	if origin.distance_to(target) < .01:
		return
	var halo := _axis("beam10", origin, target, radius, color)
	_push({"type": "halo", "key": "beam10", "obj": halo, "radius": radius}, ttl)
	var centre := _axis("beam10", origin, target, radius * .28, core)
	_push({"type": "core", "key": "beam10", "obj": centre, "radius": radius * .28}, ttl * 1.15)
	var count := maxi(1, mini(3 if low_power else 6, int(floorf(rings + .5)) + 1))
	var node := _take("beam_ring") as MultiMeshInstance3D
	node.position = Vector3.ZERO
	node.basis = Basis.IDENTITY
	node.multimesh.instance_count = count
	for index in range(count):
		node.multimesh.set_instance_color(index, _linear(core if index == 0 else color))
	_push({"type": "rings", "key": "beam_ring", "obj": node, "origin": origin,
		"axis": SourceQuaternion.vector_normalized(target - origin), "length": origin.distance_to(target), "radius": radius}, ttl * .9)
	spark(target, radius * 1.6, core)
	spark(target, radius * 2.4, color)

func ion(origin: Vector3, target: Vector3, color: int, radius: float = 2.2, ttl: float = .45,
		coil: float = 3, core: int = 0xffffff, definition: Dictionary = {}) -> void:
	if crowded():
		return
	if authored_discharge(origin, target, definition, "ion", radius, ttl):
		return
	var length := origin.distance_to(target)
	if length < .01:
		return
	var axis := SourceQuaternion.vector_normalized(target - origin)
	var throat := _axis("ion_throat", origin, target, radius, color)
	_push({"type": "ion_throat", "key": "ion_throat", "obj": throat, "radius": radius}, ttl)
	var centre := _axis("beam10", origin, target, radius * .24, core)
	_push({"type": "ion_core", "key": "beam10", "obj": centre}, ttl * .85)
	var up := Vector3.RIGHT if absf(axis.y) > .9 else Vector3.UP
	var normal_x := SourceQuaternion.vector_normalized(axis.cross(up))
	var normal_z := SourceQuaternion.vector_normalized(axis.cross(normal_x))
	var segments := 6 if low_power else 10
	var count := maxi(1, mini(2 if low_power else 4, floori(coil + .5)))
	var beads := _take("ion_beads") as MultiMeshInstance3D
	beads.position = Vector3.ZERO
	beads.basis = Basis.IDENTITY
	beads.multimesh.instance_count = segments * count
	for index in range(segments * count):
		beads.multimesh.set_instance_color(index, _linear(core if index < segments else color))
	_push({"type": "ion_beads", "key": "ion_beads", "obj": beads, "origin": origin,
		"axis": axis, "normal_x": normal_x, "normal_z": normal_z, "length": length,
		"radius": radius, "segments": segments, "coils": count}, ttl)
	var arcs := _take("ion_arcs") as MultiMeshInstance3D
	arcs.position = Vector3.ZERO
	arcs.basis = Basis.IDENTITY
	arcs.multimesh.instance_count = 7
	_tint(arcs, core)
	for index in range(7):
		var progress := (index + .4) / 7
		var phase := index * 2.3
		var radial := radius * (1.9 - 1.35 * progress)
		var point := origin + axis * progress * length + normal_x * cos(phase) * radial + normal_z * sin(phase) * radial
		var delta := normal_x * cos(phase + .6) * radius * (1.5 - progress) + normal_z * sin(phase + .6) * radius * (1.5 - progress) + axis * (.5 - (index % 2)) * radius
		var rotation := SourceQuaternion.basis(SourceQuaternion.from_unit_vectors(Vector3.UP, SourceQuaternion.vector_normalized(delta)))
		arcs.multimesh.set_instance_transform(index, Transform3D(rotation.scaled_local(Vector3(radius * .07, delta.length(), radius * .07)), point + delta * .5))
	_push({"type": "ion_arcs", "key": "ion_arcs", "obj": arcs}, ttl * .45)
	spark(target, radius * 2, core)
	spark(origin, radius * 1.7, core)

func authored_discharge(origin: Vector3, target: Vector3, definition: Dictionary, family: String, radius: float, ttl: float) -> bool:
	var key := _authored_key(definition, family)
	if key.is_empty() or origin.distance_to(target) < .01:
		return false
	var model := _take_authored(key)
	if model == null:
		return false
	model.discharge(origin, target, radius)
	_push({"type": "authored_discharge", "key": "weapon/" + key, "obj": model, "radius": radius}, ttl)
	var character: Dictionary = Content.balance.weaponEffects.characters[definition.ch]
	spark(target, radius * .5, int(character.accent))
	return true

func fan(origin: Vector3, direction: Vector3, definition: Dictionary, reach: float, clip: Callable, ttl: float = .45) -> bool:
	if crowded() or not is_finite(reach) or reach <= 0 or direction.length_squared() < .0000000001:
		return false
	var key := _authored_key(definition, "fan")
	if key.is_empty():
		return false
	var model := _take_authored(key)
	if model == null:
		return false
	model.fan(origin, direction, definition, reach, clip)
	_push({"type": "authored_fan", "key": "weapon/" + key, "obj": model}, ttl)
	return true

func fan_blast(origin: Vector3, direction: Vector3, definition: Dictionary, reach: float,
		side: String, hue: Variant, clip: Callable) -> void:
	if fan(origin, direction, definition, reach, clip):
		return
	var right := SourceQuaternion.vector_normalized(direction.cross(Vector3.UP))
	var arc: Variant = definition.get("arc")
	var half := deg_to_rad(float(arc) if ControlPreferences.truthy(arc) else 15.0)
	var plasma: bool = definition.type == "plasma"
	var fallback := (0xffcf7f if side == "SWARM" else 0x7fe8ff) if plasma else (0xffe08a if side == "SWARM" else 0xbfe6ff)
	var color := int(hue) if hue != null else fallback
	var blades := 7 if plasma else 9
	muzzle(origin, plasma, side)
	if plasma:
		var core: int = Content.balance.npcShots.colors.get(side, Content.balance.npcShots.colors[""]).hot
		var endpoint: Vector3 = clip.call(origin, origin + direction * reach * .82 * float(Content.constants.FAN_RANGE_CENTER_F)).to
		ion(origin, endpoint, color, 2.2, .45, 3, core, definition)
		shock(origin, 2.6, core)
	for index in range(blades):
		var fraction := float(index) / (blades - 1) * 2 - 1
		var ray := SourceQuaternion.rotate(SourceQuaternion.axis_angle(Vector3.UP, half * fraction), direction)
		ray = SourceQuaternion.rotate(SourceQuaternion.axis_angle(right, half * .5 * (_sample_random() * 2 - 1)), ray)
		var factor := 1 + (float(Content.constants.FAN_RANGE_CENTER_F) - 1) * (1 - absf(fraction))
		var length := reach * factor * (.7 + _sample_random() * .3 if plasma else .85 + _sample_random() * .15)
		var endpoint: Vector3 = clip.call(origin, origin + ray * length).to
		beam(origin, endpoint, color, .24 if plasma else .12, .16 if plasma else .07)
		spark(endpoint, 3 if plasma else 1.5, color)

func remote_plasma(origin: Vector3, direction: Vector3, definition: Dictionary, reach: float, arc: float,
		slot: String, side: String, hue: Variant, barrel: bool, clip: Callable) -> void:
	if not definition.is_empty() and fan(origin, direction, definition,
		reach if ControlPreferences.truthy(reach) else float(definition.range), clip):
		return
	var color := int(hue) if hue != null else 0xffcf7f if side == "SWARM" else 0x7fe8ff
	var heavy := slot != "light"
	var length := reach if ControlPreferences.truthy(reach) else 150.0
	var half := deg_to_rad(arc if ControlPreferences.truthy(arc) else 15.0)
	muzzle(origin, heavy, side)
	if heavy:
		var core: int = Content.balance.npcShots.colors.get(side, Content.balance.npcShots.colors[""]).hot
		var endpoint: Vector3 = clip.call(origin, origin + direction * length * .82).to
		ion(origin, endpoint, color, 2.2, .45 * (1.4 if barrel else 1.0), 4 if barrel else 3, core, definition)
	for index in range(-2, 3):
		var ray := SourceQuaternion.rotate(SourceQuaternion.axis_angle(Vector3.UP, half * index / 2), direction)
		var endpoint: Vector3 = clip.call(origin, origin + ray * length * .8).to
		beam(origin, endpoint, color, .26 * (1.5 if barrel else 1.0) if heavy else .2, .22 if heavy else .09)
		if barrel:
			spark(endpoint, 3.2, color)

func lance_visual(origin: Vector3, target: Vector3, definition: Dictionary, side: String, hue: Variant) -> void:
	var colors: Dictionary = Content.balance.npcShots.colors.get(side, Content.balance.npcShots.colors[""])
	if Content.balance.weaponEffects.characters.has(definition.get("ch")):
		lance(origin, target, definition, int(hue) if hue != null else int(colors.col))
		return
	var radius := float(definition.lanceRadius)
	if definition.type == "beam":
		var color := int(hue) if hue != null else 0xa8fff2 if side == "SWARM" else 0xd2b8ff
		energy_beam(origin, target, color, radius, .5, 4, int(colors.hot), definition)
		shock(origin, radius * 1.15, color)
		return
	beam(origin, target, int(colors.col), .26, radius, .28)
	beam(origin, target, int(colors.hot), .16, radius * .16)
	shock(origin, radius * 1.2, int(colors.hot))
	spark(target, radius * 1.5, int(colors.col))

func lance(origin: Vector3, target: Vector3, definition: Dictionary, color: int) -> void:
	if crowded():
		return
	var radius := float(definition.lanceRadius)
	var character: Dictionary = Content.balance.weaponEffects.characters.get(definition.get("ch"), {})
	var slot: String = str(definition.slot) if ControlPreferences.truthy(definition.get("slot")) else "heavy"
	if not character.is_empty():
		beam(origin, target, color, .5 if definition.type == "beam" else .26, radius, .14)
	var charging: bool = character.get("charging", false) and slot == "heavy"
	var burst_start := effects.size()
	if charging:
		shock(origin, radius * 1.25, color)
		spark(origin, radius * .4, color)
	if definition.type == "beam":
		energy_beam(origin, target, color, radius, .5, 4, 0xffffff, definition)
		if charging:
			for index in range(burst_start, effects.size()):
				effects[index].ttl += .09
				effects[index].start_delay = .09
				effects[index].obj.visible = false
		return
	var payload: String = character.get("payloads", {}).get(slot, "")
	if not payload.is_empty():
		if origin.distance_squared_to(target) < .0001:
			return
		var model := _take_projectile(payload)
		model.position = origin
		model.scale = Vector3.ONE
		model.quaternion = SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(target - origin))
		model.step_fx(0, 0)
		_push({"type": "lance_projectile", "key": payload, "obj": model, "origin": origin, "target": target},
			clampf(ShotHistory.flight_seconds(definition, origin.distance_to(target)), .08, .65))
		return
	if authored_discharge(origin, target, definition, "bullet", radius, .26):
		return
	beam(origin, target, color, .26, radius, .28)

func _authored_key(definition: Dictionary, family: String) -> String:
	var slot: String = str(definition.slot) if ControlPreferences.truthy(definition.get("slot")) else "heavy"
	return Content.balance.get("weaponEffects", {}).get("characters", {}).get(definition.get("ch"), {}).get("shapes", {}).get(slot, {}).get(family, "")

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0:
		return
	var over := effects.size() - int(Content.balance.npcShots.limits.maximum)
	for index in range(maxi(0, over)):
		_drop(effects.pop_front())
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		effect.ttl -= delta
		effect.age += delta
		_pose(effect, maxf(0, float(effect.ttl) / (float(effect.ttl) + float(effect.age))), delta)
		if float(effect.ttl) <= 0:
			_drop(effect)
			effects.remove_at(index)

func _push(effect: Dictionary, ttl: float) -> void:
	effect.ttl = ttl
	effect.duration = ttl
	effect.age = 0.0
	effects.append(effect)
	if effect.type not in ["projectile", "lance_projectile", "authored_discharge", "authored_fan", "sprite_gravity", "sprite_drift", "mechanical", "comic"]:
		_pose(effect, 1.0)

func _pose(effect: Dictionary, fraction: float, delta: float = 0.0) -> void:
	var node: Node3D = effect.obj
	if effect.has("start_delay"):
		var age := (1 - fraction) * (float(effect.duration) + float(effect.start_delay)) - float(effect.start_delay)
		node.visible = age >= 0
		if age < 0:
			return
		fraction = maxf(0, 1 - age / float(effect.duration))
	var opacity := 1.0
	match effect.type:
		"retired_body":
			(effect.view as RetiredBody).pose(fraction, float(effect.scale_y), bool(effect.mobile))
			return
		"missile_smoke":
			node.scale = Vector3.ONE * (1 + (1 - fraction) * 3)
			opacity = .5 * fraction
		"collapse":
			_pose_collapse(effect, fraction)
			return
		"mechanical":
			(node as MechanicalDebris).advance(fraction, delta)
			return
		"comic":
			var progress := minf(1, (1 - fraction) * float(effect.duration) / .15)
			var back := 1 + 2.2 * pow(progress - 1, 3) + 1.2 * pow(progress - 1, 2)
			node.scale = Vector3.ONE * float(effect.size) * maxf(.01, back)
			opacity = fraction / .3 if fraction < .3 else 1.0
		"sprite_gravity":
			effect.velocity.y -= 6 * delta
			node.position += effect.velocity * delta
			opacity = float(effect.opacity) * fraction
		"sprite_drift":
			var progress := 1 - fraction
			if float(effect.delay) > 0:
				node.visible = progress >= float(effect.delay)
				if not node.visible:
					return
			node.position += effect.velocity * delta
			node.scale = Vector3.ONE * (float(effect.base) + progress * float(effect.grow))
			opacity = float(effect.opacity) * fraction
		"authored_discharge":
			(node as AuthoredCombatEffect).pose_discharge(fraction, float(effect.radius))
			return
		"authored_fan":
			(node as AuthoredCombatEffect).pose_fan(fraction)
			return
		"lance_projectile":
			var origin: Vector3 = effect.origin
			node.position = origin.lerp(effect.target, 1 - fraction)
			(node as ProjectileVisual).step_fx(0, 0)
			return
		"spark":
			var age := (1 - fraction) * float(effect.duration) - float(effect.delay)
			node.visible = age >= 0
			if age < 0:
				return
			var progress := minf(1, age / .15)
			var remain := 1 - progress
			node.scale = Vector3.ONE * float(effect.radius) * (.4 + 1.4 * (1 - remain * remain))
			opacity = pow(maxf(0, 1 - progress * 1.15), 2)
		"shock":
			node.scale = Vector3.ONE * float(effect.radius) * (.15 + .85 * (1 - fraction * fraction * fraction))
			opacity = .95 * fraction * fraction
		"beam":
			node.scale.x = float(effect.width) * (.12 + .88 * fraction * fraction)
			node.scale.z = node.scale.x
			opacity = float(effect.opacity) * fraction * fraction
		"halo", "core":
			var core: bool = effect.type == "core"
			node.scale.x = float(effect.radius) * ((.2 + .8 * fraction) if core else (.25 + .75 * fraction))
			node.scale.z = node.scale.x
			opacity = .95 * fraction * fraction if core else .42 * fraction
		"ion_throat":
			node.scale.x = float(effect.radius) * (.45 + .55 * fraction)
			node.scale.z = node.scale.x
			opacity = .45 * fraction
		"ion_core":
			opacity = .9 * fraction * fraction
		"ion_arcs":
			opacity = .9 * fraction
		"ion_beads":
			var batch := node as MultiMeshInstance3D
			var segments: int = effect.segments
			var count: int = effect.coils
			var radius: float = effect.radius
			for coil_index in range(count):
				for segment in range(segments):
					var progress := fposmod((segment + .5) / segments + (1 - fraction) * .65, 1.0)
					var phase := float(coil_index) / count * TAU + progress * PI * 3 + (1 - fraction) * 7
					var radial := radius * (1.9 - 1.35 * progress)
					var point: Vector3 = effect.origin + effect.axis * progress * float(effect.length) + effect.normal_x * cos(phase) * radial + effect.normal_z * sin(phase) * radial
					var size := radius * (.30 - .20 * progress) * (.4 + fraction * .6)
					batch.multimesh.set_instance_transform(coil_index * segments + segment, Transform3D(Basis.from_scale(Vector3.ONE * size), point))
			opacity = .8 * fraction
		"rings":
			var batch := node as MultiMeshInstance3D
			var rotation := SourceQuaternion.basis(SourceQuaternion.from_unit_vectors(Vector3.BACK, effect.axis))
			for index in range(batch.multimesh.instance_count):
				var progress := minf(1, float(index) / batch.multimesh.instance_count + (1 - fraction) * 1.15)
				var size := float(effect.radius) * (.5 + progress * .5)
				batch.multimesh.set_instance_transform(index, Transform3D(rotation.scaled_local(Vector3.ONE * size),
					effect.origin + effect.axis * progress * float(effect.length)))
			opacity = .9 * fraction
		"debris":
			var batch := node as MultiMeshInstance3D
			var progress := 1 - fraction
			var radius := float(effect.radius)
			var travel := radius * .72 * (1 - fraction * fraction)
			for index in range(batch.multimesh.instance_count):
				var angle := index * 2.399963229728653
				var height := (index + .5) / batch.multimesh.instance_count
				var radial := sqrt(1 - height * height)
				var fire := index < 5
				var drift := travel * (.42 if fire else 1.0)
				var point := Vector3(cos(angle) * radial * drift,
					radius * (.08 + progress * .34) if fire else height * travel - radius * .2 * progress * progress,
					sin(angle) * radial * drift)
				var size := radius * (.24 if fire else .04 + (index % 3) * .015) * (.3 + progress) * fraction
				batch.multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(size, size * (1.4 if fire else 1.0), size)), point))
			var tint := _linear(int(effect.color)).lerp(_linear(0x433b38), progress * progress)
			batch.material_override.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
			opacity = fraction * fraction
		"projectile":
			var value := NpcShotMotion.sample(effect.plan, (1 - fraction) * float(effect.duration))
			node.position = value.position
			node.quaternion = value.quaternion
			(node as ProjectileVisual).step_fx(value.age, value.speed)
			return
	(node as GeometryInstance3D).material_override.set_shader_parameter("opacity", opacity)

func _axis(key: String, origin: Vector3, target: Vector3, radius: float, color: int) -> GeometryInstance3D:
	var node := _take(key)
	node.position = (origin + target) * .5
	node.quaternion = SourceQuaternion.from_unit_vectors(Vector3.UP, SourceQuaternion.vector_normalized(target - origin))
	node.scale = Vector3(radius, origin.distance_to(target), radius)
	_tint(node, color)
	return node

func _take(key: String) -> GeometryInstance3D:
	if not free_nodes.has(key):
		free_nodes[key] = []
	var node: GeometryInstance3D
	if not free_nodes[key].is_empty():
		node = free_nodes[key].pop_back()
	else:
		if key in ["beam_ring", "bead", "ion_beads", "ion_arcs"]:
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = MultiMesh.new()
			batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			batch.multimesh.use_colors = key in ["beam_ring", "ion_beads"]
			batch.multimesh.mesh = _geometry("bead" if key == "ion_beads" else "beam10" if key == "ion_arcs" else key)
			node = batch
		else:
			var mesh := MeshInstance3D.new()
			mesh.mesh = _geometry(key)
			node = mesh
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/combat_comic.gdshader") if key == "comic" else preload("res://shaders/combat_spark.gdshader") if key in ["spark", "sprite_fire"] else preload("res://shaders/combat_smoke.gdshader") if key == "sprite_smoke" else preload("res://shaders/combat_ring.gdshader") if key == "shock" else preload("res://shaders/combat_beam.gdshader") if key == "beam6" else preload("res://shaders/missile_smoke.gdshader") if key == "missile_smoke" else preload("res://shaders/combat_energy.gdshader")
		if key in ["comic", "spark"]:
			material.render_priority = 126 if key == "comic" else 127
		material.set_shader_parameter("curve_knee", Content.local_view_curve().knee)
		material.set_shader_parameter("curve_inverse_radius", Content.local_view_curve().inverse)
		if key == "spark":
			material.set_shader_parameter("spark_texture", load("res://assets/ui/shot-spark.png"))
		elif key in ["sprite_fire", "sprite_smoke"]:
			material.set_shader_parameter("spark_texture", load("res://assets/ui/combat-%s.png" % ("fire" if key == "sprite_fire" else "smoke")))
		material.set_meta("source_transparent", true)
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("noOutline", true)
		add_child(node)
	node.visible = true
	_tint(node, 0xffffff)
	return node

func _geometry(key: String) -> Mesh:
	if not geometries.has(key):
		if key in ["spark", "sprite_fire", "sprite_smoke", "comic"]:
			geometries[key] = QuadMesh.new()
			geometries[key].size = Vector2.ONE
		else:
			var node := (load("res://assets/npc_effects/%s.scn" % key) as PackedScene).instantiate() as MeshInstance3D
			geometries[key] = node.mesh
			node.free()
	return geometries[key]

func _take_authored(key: String) -> AuthoredCombatEffect:
	var pool_key := "weapon/" + key
	if not free_nodes.has(pool_key):
		free_nodes[pool_key] = []
	var model: AuthoredCombatEffect
	if free_nodes[pool_key].is_empty():
		model = AuthoredCombatEffect.new()
		add_child(model)
		if not model.configure(key):
			model.queue_free()
			return null
	else:
		model = free_nodes[pool_key].pop_back()
		free_authored -= 1
	return model

func _take_projectile(key: String) -> ProjectileVisual:
	if not free_nodes.has(key):
		free_nodes[key] = []
	var model: ProjectileVisual
	if free_nodes[key].is_empty():
		model = ProjectileVisual.new()
		add_child(model)
		model.configure(key)
	else:
		model = free_nodes[key].pop_back()
	model.visible = true
	return model

func _drop(effect: Dictionary) -> void:
	var node: Node3D = effect.obj
	if effect.get("type") == "retired_body":
		(effect.view as RetiredBody).dispose()
		return
	if effect.get("type") == "collapse":
		_pose_collapse(effect, 0)
		node.queue_free()
		return
	node.visible = false
	if node is AuthoredCombatEffect:
		# Unlike the source's disposable groups, native retained groups share one global cap.
		if free_authored >= int(Content.balance.npcShots.limits.maximum):
			node.queue_free()
			return
		free_authored += 1
	var limit := int(Content.balance.npcShots.limits.pools.get(effect.key, Content.balance.npcShots.limits.maximum))
	if free_nodes[effect.key].size() >= limit:
		node.queue_free()
	else:
		free_nodes[effect.key].append(node)

func _tint(node: GeometryInstance3D, color: int) -> void:
	var value := _linear(color)
	node.material_override.set_shader_parameter("tint", Vector3(value.r, value.g, value.b))

func _sample_random() -> float:
	return float(random_sample.call()) if random_sample.is_valid() else float(visual_random.randi()) / 4294967296.0

static func _linear(color: int) -> Color:
	return Color.hex((color << 8) | 0xff).srgb_to_linear()
