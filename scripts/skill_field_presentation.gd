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
	var key := [inner, outer, segments]
	if meshes.has(key):
		return meshes[key]
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var points := PackedVector3Array()
	var coordinates := PackedVector2Array()
	if inner <= 0:
		points.append(Vector3.ZERO)
		coordinates.append(Vector2(.5, .5))
	var radius := inner if inner > 0 else outer
	for row in range(2 if inner > 0 else 1):
		for index in range(segments + 1):
			var angle := float(index) / segments * TAU
			var x := radius * cos(angle)
			var y := radius * sin(angle)
			points.append(Vector3(x, 0, -y))
			coordinates.append(Vector2((x / outer + 1) / 2, (y / outer + 1) / 2))
		radius += outer - inner
	for index in range(segments):
		var indices: Array = [index + 1, index + 2, 0] if inner <= 0 else [index, index + segments + 1, index + 1,
			index + segments + 1, index + segments + 2, index + 1]
		for vertex: int in indices:
			vertices.append(points[vertex])
			uv.append(coordinates[vertex])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes[key] = mesh
	return mesh
