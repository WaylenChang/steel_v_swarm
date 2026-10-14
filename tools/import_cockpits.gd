extends Node

func _ready() -> void:
	_import.call_deferred()

func _import() -> void:
	var selection := OS.get_cmdline_user_args()
	var projectiles := selection.has("--projectiles")
	var folder := "projectiles" if projectiles else "cockpits"
	var catalog: Dictionary = Content.balance.projectileVisual.profiles if projectiles else Content.heroes
	DirAccess.make_dir_recursive_absolute("res://assets/" + folder)
	var count := 0
	for character: String in catalog:
		if not projectiles and not selection.is_empty() and character not in selection:
			continue
		var data: Dictionary = Content.read_json("res://data/%s/%s.json" % [folder, character])
		var textures: Array[ImageTexture] = []
		for encoded: String in data.textures:
			var image := Image.new()
			if image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
				push_error("Invalid source cockpit texture: " + character)
				get_tree().quit(1)
				return
			image.generate_mipmaps()
			textures.append(ImageTexture.create_from_image(image))
		var materials: Array[StandardMaterial3D] = []
		for spec: Dictionary in data.materials:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.hex((int(spec.color) << 8) | 0xff)
			material.albedo_color.a = spec.opacity
			material.roughness = spec.roughness
			material.metallic = spec.metalness
			material.cull_mode = BaseMaterial3D.CULL_DISABLED if int(spec.side) == 2 else BaseMaterial3D.CULL_FRONT if int(spec.side) == 1 else BaseMaterial3D.CULL_BACK
			if spec.unshaded:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if spec.transparent:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if int(spec.blending) == 2:
				material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.no_depth_test = not spec.depthTest
			if not spec.depthWrite:
				material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			if int(spec.texture) >= 0:
				material.albedo_texture = textures[int(spec.texture)]
			if int(spec.emission) != 0 and spec.emissionIntensity > 0:
				material.emission_enabled = true
				material.emission = Color.hex((int(spec.emission) << 8) | 0xff)
				material.emission_energy_multiplier = spec.emissionIntensity
			materials.append(material)
		var nodes: Array[Node3D] = []
		for spec: Dictionary in data.nodes:
			var node: Node3D = MeshInstance3D.new() if spec.has("mesh") else Node3D.new()
			node.name = "n_%d" % int(spec.id)
			node.set_meta("source_name", spec.name)
			var m: Array = spec.matrix
			node.transform = Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
			node.visible = spec.visible
			nodes.append(node)
			if int(spec.parent) >= 0:
				nodes[int(spec.parent)].add_child(node)
				node.owner = nodes[0]
			if spec.has("mesh"):
				node.mesh = _mesh(data.meshes[int(spec.mesh)], spec.materials, data.materials, materials)
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var scene := PackedScene.new()
		if scene.pack(nodes[0]) != OK or ResourceSaver.save(scene, "res://assets/%s/%s.scn" % [folder, character], ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("Cannot pack source cockpit: " + character)
			get_tree().quit(1)
			return
		nodes[0].free()
		count += 1
	print("PROJECTILE_IMPORT_PASS profiles=" if projectiles else "COCKPIT_IMPORT_PASS characters=", count)
	get_tree().quit()

func _mesh(spec: Dictionary, material_ids: Array, descriptions: Array, materials: Array[StandardMaterial3D]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in range(0, spec.position.size(), 3):
		vertices.append(Vector3(spec.position[i], spec.position[i + 1], spec.position[i + 2]))
	var normals := PackedVector3Array()
	for i in range(0, spec.normal.size(), 3):
		normals.append(Vector3(spec.normal[i], spec.normal[i + 1], spec.normal[i + 2]))
	var raw: Array = spec.indices
	if raw.is_empty():
		raw = range(vertices.size())
	var groups: Array = spec.groups
	if groups.is_empty():
		groups = [{"start": 0, "count": raw.size(), "materialIndex": 0}]
	var mesh := ArrayMesh.new()
	for group: Dictionary in groups:
		var material_id := int(material_ids[0 if material_ids.size() == 1 else int(group.materialIndex)])
		var desc: Dictionary = descriptions[material_id]
		var uv := PackedVector2Array()
		for i in range(0, spec.uv.size(), 2):
			var x: float = spec.uv[i] * desc.repeat[0] + desc.offset[0]
			var y: float = spec.uv[i + 1] * desc.repeat[1] + desc.offset[1]
			uv.append(Vector2(x, 1 - y if desc.flipY else y))
		var indices := PackedInt32Array()
		for i in range(int(group.start), int(group.start + group.count), 3):
			# Preserve Three.js vertices/normals while reversing Godot's front-face winding.
			indices.append_array(PackedInt32Array([int(raw[i]), int(raw[i + 2]), int(raw[i + 1])]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		if normals.size() == vertices.size():
			arrays[Mesh.ARRAY_NORMAL] = normals
		if uv.size() == vertices.size():
			arrays[Mesh.ARRAY_TEX_UV] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[material_id])
	return mesh
