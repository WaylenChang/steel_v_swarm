class_name DamageFx
extends Node3D

var stage := 1
var radius := 0.8
var plume_height := 3.0
var smoke_y := 0.0
var flame_y := 0.0
var fire := true
var surface_cracks := true
var smoke: Array[Dictionary] = []
var cracks: Array[MeshInstance3D] = []
var hot_cracks: Array[MeshInstance3D] = []
var flames: Array[Dictionary] = []
var embers: Array[Dictionary] = []
var source_size: Dictionary = {}

static func observed_stage(kind: String, hp: float, maximum: Variant, flags: Dictionary) -> int:
	if flags.get("isSelf", false) or flags.get("civ", false) or flags.get("decoy", false) or flags.get("kami", false):
		return -1
	if flags.get("neutral", false) and not Content.balance.destruction.sceneProfiles.has(kind):
		return -1
	if flags.get("collapsed", false) or not ControlPreferences.truthy(maximum) or float(maximum) <= 0:
		return -1
	if flags.get("dead", false):
		return 0
	var fraction := hp / float(maximum)
	var thresholds: Dictionary = Content.balance.destruction.damageThresholds
	return 2 if fraction <= float(thresholds.HEAVY_F) else 1 if fraction <= float(thresholds.LIGHT_F) else 0

static func source_dimensions(size: Dictionary) -> Dictionary:
	return {"radius": size.radius if ControlPreferences.truthy(size.get("radius")) else 2.0,
		"top": size.top if ControlPreferences.truthy(size.get("top")) else 3.0,
		"height": size.height if ControlPreferences.truthy(size.get("height")) else 3.0}

static func available() -> bool:
	return Content.balance.get("destruction", {}).has("damageFx") and ResourceLoader.exists("res://assets/npc_effects/damage_flame_unit.scn") \
		and ResourceLoader.exists("res://assets/ui/combat-damage-smoke.png") and ResourceLoader.exists("res://assets/ui/combat-damage-crack.png") \
		and ResourceLoader.exists("res://assets/ui/footprint-glow.png")

func configure(dimensions: Dictionary, can_burn: bool, draw_cracks: bool, sample: Callable) -> bool:
	if not available() or not sample.is_valid() or not smoke.is_empty():
		push_error("Damage FX require original resources, an isolated visual RNG and one-time configuration")
		return false
	set_meta("noOutline", true)
	source_size = dimensions.duplicate(true)
	fire = can_burn
	surface_cracks = draw_cracks
	var height := float(dimensions.height)
	var top := float(dimensions.top)
	radius = maxf(.8, float(dimensions.radius))
	plume_height = minf(20, maxf(3, height * 1.3))
	smoke_y = top * .55
	flame_y = top * .28
	for index in range(4):
		var node := _sprite("res://assets/ui/combat-damage-smoke.png", false, 0xffffff, 0)
		smoke.append({"node": node, "phase": index / 4.0, "jx": (float(sample.call()) - .5) * radius, "jz": (float(sample.call()) - .5) * radius})
	for index in range(5):
		var angle := index / 5.0 * TAU + float(sample.call()) * .8
		var y := top * (.3 + float(sample.call()) * .45)
		var width := radius * (.4 + float(sample.call()) * .28)
		var extent := height * (.2 + float(sample.call()) * .18)
		var point := Vector3(cos(angle) * radius * .44, y, sin(angle) * radius * .44)
		for hot: bool in [false, true]:
			var node := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(width, extent)
			node.mesh = quad
			node.set_meta("source_ray_side", 2)
			node.material_override = _surface(0xff5a1e if hot else 0x141416, 1, true, hot, false)
			node.position = point
			node.rotation_order = EULER_ORDER_XYZ
			node.quaternion = WeaponPresentation.source_rotation({"rotation": [(float(sample.call()) - .5) * .7, atan2(point.x, point.z), (float(sample.call()) - .5) * 1.5], "order": "XYZ"})
			_attach(node)
			(hot_cracks if hot else cracks).append(node)
	for index in range(3):
		var height_value := height * (.28 + float(sample.call()) * .18)
		var radius_value := radius * (.18 + float(sample.call()) * .1)
		var node := MeshInstance3D.new()
		node.mesh = _flame_mesh(radius_value, height_value)
		node.material_override = _surface(0xffa826 if index % 2 else 0xff5a1e, .85, false, false, true)
		var angle := float(sample.call()) * TAU
		var distance := radius * float(sample.call()) * .55
		var phase := float(sample.call()) * TAU
		node.position = Vector3(cos(angle) * distance, flame_y + height_value / 2, sin(angle) * distance)
		node.rotation_order = EULER_ORDER_XYZ
		_attach(node)
		flames.append({"node": node, "height": height_value, "phase": phase})
	for index in range(5):
		var node := _sprite("res://assets/ui/footprint-glow.png", true, 0xffb24a, 0)
		node.scale = Vector3.ONE * radius * .28
		embers.append({"node": node, "phase": float(sample.call()), "jx": (float(sample.call()) - .5) * radius,
			"jz": (float(sample.call()) - .5) * radius, "speed": .7 + float(sample.call()) * .5})
	set_stage(1)
	return true

func set_stage(value: int) -> void:
	stage = value
	var heavy := value >= 2
	for flame: Dictionary in flames:
		flame.node.visible = heavy and fire
	for node: MeshInstance3D in hot_cracks:
		node.visible = heavy and fire and surface_cracks
	for ember: Dictionary in embers:
		ember.node.visible = heavy and fire
	for index in range(cracks.size()):
		cracks[index].visible = surface_cracks and (heavy or index < 3)

func advance(delta: float, now: float, weather: Dictionary) -> void:
	if not is_finite(delta) or delta < 0 or not is_finite(now):
		return
	var direction: Array = weather.windDir
	var drift := clampf(float(weather.windAmp), 0, 2) * radius
	var local_wind := SourceQuaternion.rotate(SourceQuaternion.inverse(SourceQuaternion.from_basis(global_basis)), Vector3(direction[0], 0, direction[1]))
	var heavy := stage >= 2
	var colour := 0x968776 if not fire else 0x2a2a2e if heavy else 0x6f757c
	for particle: Dictionary in smoke:
		particle.phase = fmod(float(particle.phase) + delta * .33, 1)
		var phase := float(particle.phase)
		var node: MeshInstance3D = particle.node
		node.position = Vector3(particle.jx * (.4 + phase), smoke_y + phase * plume_height, particle.jz * (.4 + phase)) + local_wind * drift * phase * phase
		node.scale = Vector3.ONE * (radius * .5 + phase * radius * (1.9 if heavy else 1.3))
		_tint(node, colour, (.62 if heavy else .44) * sin(phase * PI))
	if not heavy:
		return
	for flame: Dictionary in flames:
		var node: MeshInstance3D = flame.node
		var k := .7 + .35 * sin(now * 9 + float(flame.phase)) + .12 * sin(now * 23 + float(flame.phase) * 2)
		node.scale = Vector3(1, k, 1)
		node.position.y = flame_y + float(flame.height) * k / 2
		node.rotation.z = -local_wind.x * minf(.4, drift / radius * .2)
		node.rotation.x = local_wind.z * minf(.4, drift / radius * .2)
	for particle: Dictionary in embers:
		particle.phase = fmod(float(particle.phase) + delta * float(particle.speed), 1)
		var phase := float(particle.phase)
		var node: MeshInstance3D = particle.node
		node.position = Vector3(particle.jx * (.3 + phase), flame_y + phase * plume_height * .9, particle.jz * (.3 + phase)) + local_wind * drift * phase
		node.material_override.set_shader_parameter("opacity", .9 * (1 - phase))
	for node: MeshInstance3D in hot_cracks:
		node.material_override.set_shader_parameter("opacity", .55 + .35 * sin(now * 6 + node.position.y))

func _attach(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("noOutline", true)
	add_child(node)

func _sprite(path: String, additive: bool, colour: int, opacity: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.set_meta("source_ray_mesh", false)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	node.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/combat_spark.gdshader") if additive else preload("res://shaders/combat_smoke.gdshader")
	material.set_shader_parameter("spark_texture", load(path))
	material.set_shader_parameter("curve_knee", Content.balance.bodyRules.curve.knee)
	material.set_shader_parameter("curve_inverse_radius", Content.balance.bodyRules.curve.inverse)
	material.set_meta("source_transparent", true)
	node.material_override = material
	_tint(node, colour, opacity)
	_attach(node)
	return node

func _surface(colour: int, opacity: float, textured: bool, additive: bool, flame: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/damage_flame.gdshader") if flame else preload("res://shaders/damage_crack_add.gdshader") if additive else preload("res://shaders/damage_crack.gdshader")
	var linear := Color.hex((colour << 8) | 0xff).srgb_to_linear()
	material.set_shader_parameter("tint", Vector3(linear.r, linear.g, linear.b))
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("textured", textured)
	if textured:
		material.set_shader_parameter("colour_texture", load("res://assets/ui/combat-damage-crack.png"))
		var rules: Dictionary = Content.balance.destruction.damageFx
		material.set_shader_parameter("depth_factor", rules.polygonOffsetFactor)
		material.set_shader_parameter("depth_units", rules.polygonOffsetUnits)
		material.set_shader_parameter("depth_unit", pow(2, -int(rules.depthBits)))
	material.set_shader_parameter("curve_knee", Content.balance.bodyRules.curve.knee)
	material.set_shader_parameter("curve_inverse_radius", Content.balance.bodyRules.curve.inverse)
	material.set_meta("source_transparent", true)
	return material

static func _tint(node: MeshInstance3D, colour: int, opacity: float) -> void:
	var linear := Color.hex((colour << 8) | 0xff).srgb_to_linear()
	node.material_override.set_shader_parameter("tint", Vector3(linear.r, linear.g, linear.b))
	node.material_override.set_shader_parameter("opacity", opacity)

static func _flame_mesh(radius_value: float, height_value: float) -> ArrayMesh:
	var source := (load("res://assets/npc_effects/damage_flame_unit.scn") as PackedScene).instantiate() as MeshInstance3D
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(vertices.size()):
		var point := vertices[index]
		vertices[index] = Vector3(float(point.x) * radius_value * 2, float(point.y) * height_value, float(point.z) * radius_value * 2)
		var normal := normals[index]
		var x := float(normal.x) / (radius_value * 2)
		var y := float(normal.y) / height_value if height_value != 0 else 0.0
		var z := float(normal.z) / (radius_value * 2)
		var length := sqrt(x * x + y * y + z * z)
		normals[index] = Vector3(x / length, y / length, z / length) if length > 0 and height_value != 0 else Vector3.ZERO
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	source.free()
	return mesh
