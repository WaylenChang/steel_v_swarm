extends Node

const Conformance = preload("res://scripts/water_conformance.gd")

var assertions := 0
var failures := 0
var query_differences: Array = []
var buffer_differences: Array = []

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _double(hex: String) -> float:
	return hex.hex_decode().decode_double(0)

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _point(words: Array) -> Vector3:
	return Vector3(_double(words[0]), _double(words[1]), _double(words[2]))

func _bindings(records: Array) -> Array:
	var result: Array = []
	for spec: Dictionary in records:
		var parameters: Variant = null
		if spec.parameters != null:
			parameters = {}
			for key: String in spec.parameters:
				parameters[key] = null if spec.parameters[key] == null else _double(spec.parameters[key])
		result.append({"water": spec.water, "parameters": parameters,
			"position": spec.position.map(func(word: String): return _double(word))})
	return result

func _group(bindings: Array, shared: Mesh) -> Node3D:
	var root := Node3D.new()
	for spec: Dictionary in bindings:
		var node := MeshInstance3D.new()
		node.mesh = shared
		node.position = Vector3(spec.position[0], spec.position[1], spec.position[2])
		node.quaternion = Quaternion(.5, -.5, .5, .5)
		node.scale = Vector3(.75, 1.5, 2)
		root.add_child(node)
	add_child(root)
	for node in root.get_children():
		node.owner = root
	return root

func _geometry(mesh: ArrayMesh, expected: Dictionary) -> void:
	for key: String in ["positions", "normals"]:
		var native_hex: String = mesh.get_meta("source_water_" + key).to_byte_array().hex_encode()
		var source_hex: String = expected.vertices if key == "positions" else expected.normals
		if native_hex != source_hex:
			var words: Array = []
			for offset in range(0, mini(native_hex.length(), source_hex.length()), 8):
				if native_hex.substr(offset, 8) != source_hex.substr(offset, 8):
					words.append({"word": offset / 8, "native": native_hex.substr(offset, 8), "source": source_hex.substr(offset, 8)})
			buffer_differences.append({"kind": key, "words": words})
	_check(mesh.get_meta("source_water_positions").to_byte_array().hex_encode() == expected.vertices,
		"Original complete Float32 conformed position stream")
	_check(mesh.get_meta("source_water_normals").to_byte_array().hex_encode() == expected.normals,
		"Original double cross products and per-add Float32 normal accumulation")
	var source_indices: PackedInt32Array = mesh.get_meta("source_water_indices")
	_check(source_indices == PackedInt32Array(expected.indices), "Original complete 28-triangle fan order")
	var arrays := mesh.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_VERTEX].to_byte_array().hex_encode() == expected.vertices,
		"Native resource retains every Float32 vertex word")
	_check(arrays[Mesh.ARRAY_TEX_UV] == null and not expected.uv, "Replacement geometry has no fabricated UV coordinates")
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for offset in range(0, indices.size(), 3):
		_check(indices[offset] == source_indices[offset] and indices[offset + 1] == source_indices[offset + 2]
			and indices[offset + 2] == source_indices[offset + 1], "Native fan retains the source front face")
	var original: PackedVector3Array = mesh.get_meta("source_water_normals")
	var native: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(original.size()):
		# Zero-radius triangles have no area or observable normal direction.
		if original[index].length_squared() != 0:
			_check(original[index].dot(native[index]) > .999999, "Native normal direction retains the existing mesh precision bound")

func _case(item: Dictionary, index: int) -> void:
	var bindings := _bindings(item.bindings)
	var shared := BoxMesh.new()
	var material := StandardMaterial3D.new()
	shared.material = material
	var root := _group(bindings, shared)
	var sibling := _group(bindings, shared)
	var cursor := {"at": 0}
	var query := func(x: float, z: float):
		var at := int(cursor.at)
		cursor.at += 1
		if at >= item.queries.size():
			return NAN
		var expected: Array = item.queries[at]
		if _bits(x) != expected[0] or _bits(z) != expected[1]:
			query_differences.append({"case": index, "query": at, "expected": expected.slice(0, 2), "native": [_bits(x), _bits(z)]})
		return _double(expected[2])
	var owner := Conformance.new()
	_check(owner.apply(root, bindings, _double(item.center[0]), _double(item.center[1]), _double(item.center[2]), query),
		"Original ordered water and prop conformance program completes")
	_check(cursor.at == item.queries.size(), "Original complete surface query count and child order")
	for child_index in range(bindings.size()):
		var node: MeshInstance3D = root.get_child(child_index)
		var expected: Dictionary = item.nodes[child_index]
		_check(node.position == _point(expected.position) and node.scale == _point(expected.scale), "Original per-child surface offset and retained source scale")
		var q: Array = expected.quaternion.map(func(word: String): return _double(word))
		_check(absf(node.quaternion.dot(Quaternion(q[0], q[1], q[2], q[3]))) > .999999, "Water resets orientation while non-water retains its source pose")
		_check((node.mesh != shared) == bool(expected.replaced), "Only explicit water with geometry parameters replaces geometry")
		_check(sibling.get_child(child_index).mesh == shared, "Conformance never mutates another instance's shared geometry")
		if expected.replaced:
			_geometry(node.mesh, expected)
			_check(node.mesh.surface_get_material(0) == material, "Replacement retains its original material without mutation")
	var packed := PackedScene.new()
	_check(packed.pack(root) == OK, "Pack populated water and prop nodes")
	var path := "res://artifacts/sol/water-conformance/case_%d.scn" % index
	_check(ResourceSaver.save(packed, path) == OK, "Save complete private conformed resources")
	var loaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null, "Fresh native resource reload succeeds")
	if loaded != null:
		var restored: Node3D = loaded.instantiate()
		for child_index in range(item.nodes.size()):
			if item.nodes[child_index].replaced:
				_geometry(restored.get_child(child_index).mesh, item.nodes[child_index])
		restored.free()
	root.free()
	sibling.free()

func _interruptions() -> void:
	var bindings := [{"water": true, "parameters": {"radiusTop": 6}, "position": [0, .32, 0]},
		{"water": false, "parameters": null, "position": [2, .5, 3]}]
	for interruption in ["queued", "detach", "replace", "reentrant", "invalid"]:
		var shared := BoxMesh.new()
		var root := _group(bindings, shared)
		var owner := Conformance.new()
		var counter := {"calls": 0}
		var surface := func(_x: float, _z: float):
			counter.calls += 1
			if counter.calls == 2:
				match interruption:
					"queued": root.queue_free()
					"detach": remove_child(root)
					"replace":
						var old := root.get_child(1)
						root.remove_child(old)
						old.free()
						root.add_child(MeshInstance3D.new())
					"reentrant": owner.apply(root, bindings, 0, 0, 0, func(_a: float, _b: float): return 7.0)
					"invalid": return NAN
			return 0.0
		_check(not owner.apply(root, bindings, 0, 0, 0, surface), "Interrupted water conformance rejects stale continuation: " + interruption)
		_check(counter.calls == 2, "Interruption stops before the next surface query")
		if interruption != "reentrant":
			_check(root.get_child(0).mesh == shared, "Interrupted construction never publishes incomplete geometry")
		else:
			_check(root.get_child(0).mesh != shared and root.get_child(1).position.y == 7.5, "Reentrant replacement retains its completed private geometry and prop pose")
		root.free()
	var invalid_root := _group(bindings, BoxMesh.new())
	var owner := Conformance.new()
	var counter := {"calls": 0}
	var query := func(_x: float, _z: float):
		counter.calls += 1
		return 0.0
	_check(not owner.apply(invalid_root, [{"position": [0, 0, 0]}, bindings[1]], 0, 0, 0, query)
		and counter.calls == 0, "Missing source flags/parameters reject before sampling terrain")
	invalid_root.get_child(1).queue_free()
	_check(not owner.apply(invalid_root, bindings, 0, 0, 0, query) and counter.calls == 0,
		"Queued source children reject before sampling terrain")
	invalid_root.free()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/water_conformance.json")
	var profile: Dictionary = Content.read_json("res://data/water_conformance.json")
	_check(profile.get("formatVersion") == 1 and profile.get("source") == capture.source
		and profile.get("unitRing") == capture.unitRing, "Runtime radial geometry is the complete original Chromium unit fan")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current water conformance producer: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original water conformance input: " + path)
	_check(DisplayServer.get_name() != "headless", "Native packing and reload require a real driver")
	DirAccess.make_dir_recursive_absolute("res://artifacts/sol/water-conformance")
	if failures == 0:
		for index in range(capture.cases.size()):
			_case(capture.cases[index], index)
		_interruptions()
	_check(query_differences.is_empty(), "Original Chromium surface query coordinates retain exact source double words")
	var report := FileAccess.open("res://artifacts/sol/water-conformance/report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "queryDifferences": query_differences, "bufferDifferences": buffer_differences}, "  "))
	report.close()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("WATER_CONFORMANCE assertions=", assertions, " failures=", failures, " query_differences=", query_differences.size())
	get_tree().quit(0 if failures == 0 else 1)
