class_name WaterConformance
extends RefCounted

var revision := 0
var unit_ring := PackedFloat64Array()

func _load_ring() -> bool:
	if unit_ring.size() == 56:
		return true
	var path := "res://data/water_conformance.json"
	if not FileAccess.file_exists(path):
		return false
	var data: Dictionary = Content.read_json(path)
	if data.get("formatVersion") != 1 or not data.get("unitRing") is Array or data.unitRing.size() != 56:
		return false
	var words := PackedFloat64Array()
	for word: Variant in data.unitRing:
		if not word is String or word.length() != 16 or not word.is_valid_hex_number():
			return false
		var value: float = word.hex_decode().decode_double(0)
		if not is_finite(value):
			return false
		words.append(value)
	unit_ring = words
	return true

# Bindings are original immediate-child records, including absent geometry parameters.
# Surface queries must seed the original unified surface with terrain.heightAt(x, z).
# Never infer the water flag or a radius from imported bounds.
func apply(group: Node3D, bindings: Array, cx: float, cz: float, cy: float, surface: Callable) -> bool:
	revision += 1
	var token := revision
	if not is_instance_valid(group) or group.is_queued_for_deletion() or not surface.is_valid():
		return false
	var nodes := group.get_children()
	var parent_id := group.get_parent().get_instance_id() if group.get_parent() != null else 0
	if not _current(token, group, nodes, parent_id):
		return false
	if nodes.size() != bindings.size() or not is_finite(cx) or not is_finite(cz) or not is_finite(cy):
		return false
	for index in range(bindings.size()):
		var spec: Variant = bindings[index]
		if not nodes[index] is Node3D or not spec is Dictionary or not spec.get("water") is bool:
			return false
		if not spec.get("position") is Array or spec.position.size() != 3:
			return false
		for value: Variant in spec.position:
			if not _number(value):
				return false
		if not spec.has("parameters") or (spec.parameters != null and not spec.parameters is Dictionary):
			return false
		if spec.water and spec.parameters != null:
			if not nodes[index] is MeshInstance3D or nodes[index].mesh == null or nodes[index].mesh.get_surface_count() == 0:
				return false
			if not _number(_radius(spec.parameters)):
				return false
			if not _load_ring():
				return false
	for index in range(bindings.size()):
		var spec: Dictionary = bindings[index]
		var node: Node3D = nodes[index]
		var x := float(spec.position[0])
		var y := float(spec.position[1])
		var z := float(spec.position[2])
		if spec.water and spec.parameters != null:
			var off := 0.0 if y == 0 else y
			var radius := float(_radius(spec.parameters))
			var vertices := PackedVector3Array()
			var height: Variant = surface.call(cx, cz)
			if not _current(token, group, nodes, parent_id) or not _number(height):
				return false
			vertices.append(Vector3(0, float(height) - cy + off, 0))
			for part in range(28):
				var dx := float(unit_ring[part * 2]) * radius
				var dz := float(unit_ring[part * 2 + 1]) * radius
				height = surface.call(cx + dx, cz + dz)
				if not _current(token, group, nodes, parent_id) or not _number(height):
					return false
				vertices.append(Vector3(dx, float(height) - cy + off, dz))
			var indices := PackedInt32Array()
			for part in range(28):
				indices.append_array(PackedInt32Array([0, 1 + part, 1 + (part + 1) % 28]))
			var normals := _normals(vertices, indices)
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			# Godot's front-face winding is opposite Three.js; source normals stay unchanged.
			var native_indices := indices.duplicate()
			for part in range(0, native_indices.size(), 3):
				native_indices[part + 1] = indices[part + 2]
				native_indices[part + 2] = indices[part + 1]
			arrays[Mesh.ARRAY_INDEX] = native_indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, node.mesh.surface_get_material(0))
			mesh.set_meta("source_water_positions", vertices)
			mesh.set_meta("source_water_normals", normals)
			mesh.set_meta("source_water_indices", indices)
			node.mesh = mesh
			if not _current(token, group, nodes, parent_id):
				return false
			node.position = Vector3.ZERO
			if not _current(token, group, nodes, parent_id):
				return false
			node.quaternion = Quaternion.IDENTITY
		else:
			var height: Variant = surface.call(cx + x, cz + z)
			if not _current(token, group, nodes, parent_id) or not _number(height):
				return false
			node.position = Vector3(x, y + (float(height) - cy), z)
		if not _current(token, group, nodes, parent_id):
			return false
	return true

func _current(token: int, group: Node3D, nodes: Array[Node], parent_id: int) -> bool:
	if token != revision or not is_instance_valid(group) or group.is_queued_for_deletion():
		return false
	var parent := group.get_parent()
	if (parent.get_instance_id() if parent != null else 0) != parent_id:
		return false
	while parent != null:
		if parent.is_queued_for_deletion():
			return false
		parent = parent.get_parent()
	if group.get_child_count() != nodes.size():
		return false
	for index in range(nodes.size()):
		if not is_instance_valid(nodes[index]) or nodes[index].is_queued_for_deletion() or group.get_child(index) != nodes[index]:
			return false
	return true

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _radius(parameters: Dictionary) -> Variant:
	var result: Variant = parameters.get("radiusTop")
	if result == null:
		result = parameters.get("radius")
	return 6.0 if result == null else result

static func _normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var words := PackedFloat32Array()
	words.resize(vertices.size() * 3)
	for offset in range(0, indices.size(), 3):
		var a := vertices[indices[offset]]
		var b := vertices[indices[offset + 1]]
		var c := vertices[indices[offset + 2]]
		# Three reads Float32 positions, computes in double, then rounds each accumulation.
		var cbx := float(c.x) - float(b.x)
		var cby := float(c.y) - float(b.y)
		var cbz := float(c.z) - float(b.z)
		var abx := float(a.x) - float(b.x)
		var aby := float(a.y) - float(b.y)
		var abz := float(a.z) - float(b.z)
		var nx := cby * abz - cbz * aby
		var ny := cbz * abx - cbx * abz
		var nz := cbx * aby - cby * abx
		for corner in range(3):
			var index := indices[offset + corner] * 3
			words[index] = float(words[index]) + nx
			words[index + 1] = float(words[index + 1]) + ny
			words[index + 2] = float(words[index + 2]) + nz
	var result := PackedVector3Array()
	for index in range(0, words.size(), 3):
		var x := float(words[index])
		var y := float(words[index + 1])
		var z := float(words[index + 2])
		var length := sqrt(x * x + y * y + z * z)
		var inverse := 1.0 / length if length != 0 else 1.0
		result.append(Vector3(x * inverse, y * inverse, z * inverse))
	return result
