extends Node

var assertions := 0
var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func _source(reference: Dictionary) -> void:
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(reference.formatVersion == 1, "Load original fog geometry constructors")
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == reference.source.inputs[path], "Current fog geometry producer: " + path)
	for path: String in reference.source.sourceInputs:
		_check(provenance.inputs[path] == reference.source.sourceInputs[path], "Original fog dependency matches imported provenance: " + path)

func _geometry(mesh: ArrayMesh, transform: Transform3D, expected: Dictionary) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	_check(vertices.size() == expected.vertices.size(), "Original fog triangle count and complete order")
	_check(normals.size() == vertices.size() and coordinates.size() == vertices.size(), "Original fog normals and UV streams remain complete")
	if normals.size() != vertices.size() or coordinates.size() != vertices.size():
		return
	for index in range(mini(vertices.size(), expected.vertices.size())):
		_check((transform * vertices[index]).distance_to(_point(expected.vertices[index])) < .00001,
			"Original ordered disk/ring vertex writes within native float precision")
		_check((transform.basis * normals[index]).dot(_point(expected.normals[index])) > .999999,
			"Original rotated positive-Z normals")
		var uv := Vector2(expected.uv[index * 2], expected.uv[index * 2 + 1])
		_check(coordinates[index] == uv, "Original Float32 UV writes survive native storage and reload")

func _cases(reference: Dictionary) -> void:
	var output := "res://artifacts/sol/fog-geometry"
	DirAccess.make_dir_recursive_absolute(output)
	for case_index in range(reference.cases.size()):
		var item: Dictionary = reference.cases[case_index]
		var view := SkillFieldPresentation.new()
		add_child(view)
		var root := view._fog(item.radius, item.ally)
		_check(root.get_child_count() == item.nodes.size(), "Original fog disk and five cloud rings")
		for index in range(mini(root.get_child_count(), item.nodes.size())):
			var node := root.get_child(index) as MeshInstance3D
			var expected: Dictionary = item.nodes[index]
			_geometry(node.mesh, node.transform, expected)
			var material := node.material_override as StandardMaterial3D
			_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				and material.cull_mode == BaseMaterial3D.CULL_DISABLED and int(expected.side) == 2,
				"Original unlit double-sided fog material")
			_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and expected.transparent
				and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS and expected.depthWrite,
				"Original transparent fog retains depth writes")
			_check(absf(material.albedo_color.a - float(expected.opacity)) < .0000001
				and material.albedo_color.to_html(false) == Color.hex((int(expected.color) << 8) | 255).to_html(false),
				"Original ally/enemy colors and per-layer opacity")
			var path := "%s/%d-%d.res" % [output, case_index, index]
			var saved := ResourceSaver.save(node.mesh, path)
			_check(saved == OK, "Save the native fog geometry resource")
			if saved == OK:
				var reloaded := ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
				_check(reloaded != null, "Reload original fog geometry through native resources")
				if reloaded != null:
					_geometry(reloaded, node.transform, expected)
		view.free()

func _isolation() -> void:
	var view := SkillFieldPresentation.new()
	add_child(view)
	var first := view._fog(35, true)
	var second := view._fog(35, true)
	for index in range(first.get_child_count()):
		var left := first.get_child(index) as MeshInstance3D
		var right := second.get_child(index) as MeshInstance3D
		_check(left.mesh == right.mesh and left.material_override != right.material_override,
			"Fog instances reuse immutable geometry and retain private opacity materials")
	var original: Color = second.get_child(0).material_override.albedo_color
	first.get_child(0).material_override.albedo_color.a = .01
	_check(second.get_child(0).material_override.albedo_color == original, "One fog's fade cannot mutate another fog")
	var radius: float = 35.000004
	var narrow := view._ring(0, radius, 24)
	_check(narrow != view._ring(0, 35, 24) and narrow == view._ring(0, radius, 24),
		"Geometry cache keys retain exact radius identity and stable reuse")
	view.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fog geometry qualification requires the real renderer")
		get_tree().quit(1)
		return
	var reference: Dictionary = Content.read_json("res://tests/fixtures/fog_geometry.json")
	_source(reference)
	if failures.is_empty():
		_cases(reference)
		_isolation()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("FOG_GEOMETRY_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
