class_name SkillFieldPresentation
extends Node3D

var fog_nodes: Dictionary = {}
var meshes: Dictionary = {}

func sync_fogs(states: Array, side: String, now: float) -> void:
	var seen := {}
	for state: Dictionary in states:
		var id := int(state.id)
		if float(state.until) <= now:
			continue
		seen[id] = true
		var ally: bool = state.side == side
		if not fog_nodes.has(id) or fog_nodes[id].get_meta("ally") != ally:
			if fog_nodes.has(id):
				fog_nodes[id].queue_free()
			fog_nodes[id] = _fog(state.radius, ally)
		var node: Node3D = fog_nodes[id]
		var point: Vector2 = state.center
		node.position = Vector3(point.x, 0.5, point.y)
		node.rotation.y = maxf(0, now - float(state.start)) * 0.2
		var base := 0.28 if ally else 0.85
		var remaining := maxf(0, float(state.until) - now) / float(state.duration)
		var material: StandardMaterial3D = node.get_child(0).material_override
		material.albedo_color.a = base if remaining > 0.2 else base * remaining / 0.2
	for id in fog_nodes.keys():
		if not seen.has(id):
			fog_nodes[id].queue_free()
			fog_nodes.erase(id)

func _fog(radius: float, ally: bool) -> Node3D:
	var root := Node3D.new()
	root.set_meta("ally", ally)
	add_child(root)
	var color := Color.hex(0x7fa8d8ff if ally else 0x4a5568ff)
	var opacity := 0.28 if ally else 0.85
	_add_surface(root, _ring(0, radius, 24), color, opacity, 0)
	for index in range(5):
		_add_surface(root, _ring(radius * (0.2 + index * 0.15), radius * (0.4 + index * 0.15), 16), color, opacity * 0.7, 1 + index * 0.8)
	return root

func _add_surface(root: Node3D, mesh: ArrayMesh, color: Color, opacity: float, altitude: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.y = altitude
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, opacity)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)

func _ring(inner: float, outer: float, segments: int) -> ArrayMesh:
	var key := "%s/%s/%d" % [inner, outer, segments]
	if meshes.has(key):
		return meshes[key]
	var vertices := PackedVector3Array()
	for index in range(segments):
		var first := index * TAU / segments
		var last := (index + 1) * TAU / segments
		var a_inner := Vector3(cos(first) * inner, 0, -sin(first) * inner)
		var a_outer := Vector3(cos(first) * outer, 0, -sin(first) * outer)
		var b_inner := Vector3(cos(last) * inner, 0, -sin(last) * inner)
		var b_outer := Vector3(cos(last) * outer, 0, -sin(last) * outer)
		if inner <= 0:
			vertices.append_array(PackedVector3Array([Vector3.ZERO, a_outer, b_outer]))
		else:
			vertices.append_array(PackedVector3Array([a_inner, a_outer, b_inner, a_outer, b_outer, b_inner]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes[key] = mesh
	return mesh
