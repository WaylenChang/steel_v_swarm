class_name AuthoredCombatEffect
extends Node3D

var profile: Dictionary = {}
var parts: Array[Dictionary] = []

static func available() -> bool:
	var rules: Dictionary = Content.balance.get("weaponEffects", {})
	if rules.is_empty():
		return false
	for key: String in rules.shapes:
		if not ResourceLoader.exists("res://assets/weapon_effects/%s.scn" % key):
			return false
	for item: Dictionary in rules.characters.values():
		for key: String in item.payloads.values():
			if not Content.balance.projectileVisual.profiles.has(key) or not ResourceLoader.exists("res://assets/projectiles/%s.scn" % key):
				return false
	return true

func configure(key: String) -> bool:
	profile = Content.balance.weaponEffects.shapes[key]
	var source := (load("res://assets/weapon_effects/%s.scn" % key) as PackedScene).instantiate() as Node3D
	add_child(source)
	_collect(source)
	if parts.is_empty():
		push_error("Missing original authored effect geometry: " + key)
		return false
	if profile.family == "fan":
		for part: Dictionary in parts:
			var data: Dictionary = part.source
			if not data.get("positions") is Array or not data.get("bins") is Array or data.positions.size() != data.bins.size() * 3:
				push_error("Missing original fan vertex ownership: " + key)
				return false
	return true

func _collect(node: Node3D) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var source := mesh.get_active_material(0) as BaseMaterial3D
		var color := source.albedo_color.srgb_to_linear()
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/combat_energy.gdshader")
		material.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
		material.set_shader_parameter("opacity", source.get_meta("source_opacity"))
		material.set_shader_parameter("curve_knee", Content.local_view_curve().knee)
		material.set_shader_parameter("curve_inverse_radius", Content.local_view_curve().inverse)
		material.set_meta("source_transparent", true)
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_meta("noOutline", true)
		mesh.set_meta("presentationEffect", true)
		parts.append({"mesh": mesh, "material": material, "alpha": source.get_meta("source_opacity"),
			"arrays": mesh.mesh.surface_get_arrays(0), "source": mesh.get_meta("source_effect", {})})
	for child: Node3D in node.get_children():
		_collect(child)

func reset() -> void:
	position = Vector3.ZERO
	quaternion = Quaternion.IDENTITY
	scale = Vector3.ONE
	visible = true
	for part: Dictionary in parts:
		part.material.set_shader_parameter("opacity", part.alpha)
		part.material.set_shader_parameter("sweep", false)

func discharge(origin: Vector3, target: Vector3, radius: float) -> void:
	reset()
	position = origin
	quaternion = SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(target - origin))
	scale = Vector3(radius, radius, origin.distance_to(target))

func fan(origin: Vector3, direction: Vector3, definition: Dictionary, reach: float, clip: Callable) -> void:
	reset()
	position = origin
	for part: Dictionary in parts:
		var source: Dictionary = part.source
		var arrays: Array = part.arrays.duplicate(true)
		arrays[Mesh.ARRAY_VERTEX] = FanEffectGeometry.vertices(source.positions, source.bins, int(profile.ownership.count),
			definition, origin, direction, reach, clip)
		arrays[Mesh.ARRAY_COLOR] = null
		var bins := PackedVector2Array()
		for bin: int in source.bins:
			bins.append(Vector2(bin, 0))
		arrays[Mesh.ARRAY_TEX_UV] = bins
		if not part.has("geometry"):
			part.geometry = ArrayMesh.new()
			part.mesh.mesh = part.geometry
		part.geometry.clear_surfaces()
		part.geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func pose_discharge(fraction: float, radius: float) -> void:
	var weight := BodyReferenceMotion.sample_keys(profile.envelope, 1 - fraction)
	scale.x = radius * (.15 + .85 * weight)
	scale.y = scale.x
	for part: Dictionary in parts:
		part.material.set_shader_parameter("opacity", float(part.alpha) * weight)

func pose_fan(fraction: float) -> void:
	var ownership: Dictionary = profile.ownership
	var time := 1 - fraction
	var radius := BodyReferenceMotion.sample_keys(ownership.radiusKeys, time) if ControlPreferences.truthy(ownership.get("radiusKeys")) else .3 + .7 * fraction
	var opacity := BodyReferenceMotion.sample_keys(ownership.opacityKeys, time) if ControlPreferences.truthy(ownership.get("opacityKeys")) else fraction
	scale = Vector3.ONE * radius
	for part: Dictionary in parts:
		part.material.set_shader_parameter("opacity", float(part.alpha) * opacity)
		part.material.set_shader_parameter("sweep", ownership.get("motion") == "sweep")
		part.material.set_shader_parameter("sweep_time", time)
		part.material.set_shader_parameter("sweep_bins", maxf(1, float(ownership.count) - 1))
