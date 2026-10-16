class_name LockGlowPresentation
extends Node3D

var target_id := 0
var target: BattleUnit
var dimensions: Dictionary = {}
var halo: MeshInstance3D
var ring: MeshInstance3D
var halo_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var flash_at := -1e9

static func warning_until(previous: float, event: Dictionary, viewer_peer: int, now: float) -> float:
	if event.get("type") != "lock" or int(event.get("peer", 0)) == viewer_peer or int(event.get("target_peer", 0)) != viewer_peer:
		return previous
	return now + float(Content.constants.LOCK.WARN_S)

static func pose(size: Dictionary, now: float, hit_at: float = -1e9) -> Dictionary:
	var radius: float = maxf(1.5, float(size.radius) * 1.5)
	var diameter: float = maxf(3.0, maxf(size.height, size.radius * 2) * 1.15)
	var pulse := 0.5 + 0.5 * sin(now * 6)
	var flash := maxf(0, 1 - (now - hit_at) / 0.2) if hit_at != 0 else 0.0
	return {"radius": radius, "centre": size.top - size.height * 0.5,
		"halo_size": diameter * (0.92 + pulse * 0.16 + flash * 0.55),
		"halo_opacity": minf(1, 0.3 + pulse * 0.35 + flash * 0.6),
		"ring_scale": 0.94 + pulse * 0.12 + flash * 0.45,
		"ring_opacity": minf(1, 0.9 + flash * 0.6), "ring_angle": -now * 1.6}

func _prepare() -> void:
	if halo != null:
		return
	halo_material = StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	halo_material.no_depth_test = true
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.billboard_keep_scale = true
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_texture = load("res://assets/ui/footprint-glow.png")
	halo = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	halo.mesh = quad
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	ring_material = halo_material.duplicate()
	ring_material.albedo_texture = null
	ring_material.no_depth_test = false
	ring_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	var profile: Dictionary = Content.balance.aimingPresentation.lockRing
	var vertices := PackedVector3Array()
	for point: Array in profile.vertices:
		vertices.append(Vector3(point[0], 0, point[1]))
	var indices := PackedInt32Array()
	for index in range(0, profile.indices.size(), 3):
		indices.append_array([int(profile.indices[index]), int(profile.indices[index + 2]), int(profile.indices[index + 1])])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ring = MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.3
	add_child(ring)

func clear() -> void:
	target_id = 0
	target = null
	visible = false
	flash_at = -1e9

func apply(units: Dictionary, state: Dictionary) -> bool:
	var id := int(state.get("anchor", 0))
	var unit: BattleUnit = units.get(id)
	if id == 0 or int(state.get("target", 0)) != id or unit == null or not unit.alive() or not unit.presentation_visible:
		clear()
		return false
	if id == target_id and unit == target:
		return false
	var measured := unit.visual_dimensions()
	if measured.is_empty():
		clear()
		return false
	_prepare()
	target_id = id
	target = unit
	dimensions = measured.duplicate()
	flash_at = -1e9
	var color := Color(Content.side_info(unit.side).color)
	halo_material.albedo_color = color
	ring_material.albedo_color = color
	visible = true
	return true

func flash(now: float) -> void:
	if target_id != 0 and is_finite(now):
		flash_at = now

func advance(now: float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.alive() or not target.presentation_visible:
		clear()
		return
	global_transform = target.global_transform
	var state := pose(dimensions, now, flash_at)
	halo.position.y = state.centre
	halo.scale = Vector3.ONE * state.halo_size
	var color := halo_material.albedo_color
	color.a = state.halo_opacity
	halo_material.albedo_color = color
	color.a = state.ring_opacity
	ring_material.albedo_color = color
	ring.rotation.y = state.ring_angle
	ring.scale = Vector3.ONE * state.radius * state.ring_scale
