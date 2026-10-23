extends Node

const ResourcePublisher = preload("res://tools/source_resource_publisher.gd")

var source_textures := SourceTextureImages.new()
var cel_data: SourceCelData

func _ready() -> void:
	_import.call_deferred()

func _import() -> void:
	var selection := OS.get_cmdline_user_args()
	var projectiles := selection.has("--projectiles")
	var companions := selection.has("--companions")
	var hazards := selection.has("--hazards")
	var loot := selection.has("--loot")
	var bodies := selection.has("--bodies")
	var civilians := selection.has("--civilian-parts")
	var npc_effects := selection.has("--npc-effects")
	var weapon_effects := selection.has("--weapon-effects")
	var first_person_shields := selection.has("--first-person-shields")
	var folder := "first_person_shields" if first_person_shields else "weapon_effects" if weapon_effects else "npc_effects" if npc_effects else "civilian_parts" if civilians else "bodies" if bodies else "loot" if loot else "hazards" if hazards else "companions" if companions else "projectiles" if projectiles else "cockpits"
	var catalog: Dictionary = Content.balance.firstPersonShields if first_person_shields else Content.balance.weaponEffects.shapes if weapon_effects else Content.balance.npcShots.shapes if npc_effects else Content.balance.civilian_visuals.profiles if civilians else Content.balance.bodies if bodies else Content.balance.loot_visuals if loot else Content.balance.hazard_visuals if hazards else Content.balance.companions if companions else Content.balance.projectileVisual.profiles if projectiles else Content.heroes
	DirAccess.make_dir_recursive_absolute("res://assets/" + folder)
	var count := 0
	for character: String in catalog:
		if not first_person_shields and not weapon_effects and not npc_effects and not civilians and not bodies and not projectiles and not companions and not hazards and not loot and not selection.is_empty() and character not in selection:
			continue
		var data: Dictionary = Content.read_json("res://data/%s/%s.json" % [folder, character])
		if DisplayServer.get_name() == "headless" and data.nodes.any(func(spec): return spec.has("instances") and not spec.instances.is_empty()):
			push_error("Native MultiMesh packing requires a real rendering driver: " + character)
			get_tree().quit(1)
			return
		if not source_textures.configure(data.get("textureImages", [])) or not _prepare_textures(data):
			get_tree().quit(1)
			return
		var textures: Array[ImageTexture] = []
		cel_data = SourceCelData.new()
		if not cel_data.configure(data, source_textures):
			get_tree().quit(1)
			return
		for index in range(data.textures.size()):
			var image: Image
			if index < source_textures.images.size():
				image = source_textures.images[index].duplicate()
			else:
				image = Image.new()
				if image.load_png_from_buffer(Marshalls.base64_to_raw(data.textures[index])) != OK:
					push_error("Invalid source cockpit texture: " + character)
					get_tree().quit(1)
					return
			if not image.get_meta("source_manual_mipmaps", false) and image.generate_mipmaps() != OK:
				push_error("Cannot generate native source cockpit mipmaps: " + character)
				get_tree().quit(1)
				return
			textures.append(ImageTexture.create_from_image(image))
		var materials: Array[Material] = []
		for spec: Dictionary in data.materials:
			if spec.get("type") == "shield":
				var shield := ShieldPresentation.material(spec, textures, Content.balance.bodyRules.curve)
				shield.resource_local_to_scene = true
				shield.set_meta("source_material_id", materials.size())
				materials.append(shield)
				continue
			var material := StandardMaterial3D.new()
			material.resource_local_to_scene = bodies
			material.set_meta("source_material_id", materials.size())
			if spec.has("cel"):
				if not cel_data.attach(material, spec.cel):
					get_tree().quit(1)
					return
			material.albedo_color = Color.hex((int(spec.color) << 8) | 0xff)
			material.albedo_color.a = spec.opacity
			material.set_meta("source_transparent", bool(spec.transparent))
			material.set_meta("source_dissolve", bool(spec.get("dissolve", false)))
			material.set_meta("source_alpha_test", float(spec.get("alphaTest", 0)))
			material.set_meta("source_opacity", spec.opacity)
			material.set_meta("source_depth_write", bool(spec.depthWrite))
			material.set_meta("source_emissive_intensity", spec.emissionIntensity)
			material.vertex_color_use_as_albedo = bool(spec.get("vertexColors", false))
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
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if spec.depthWrite else BaseMaterial3D.DEPTH_DRAW_DISABLED
			if spec.has("sourceTexture"):
				material.albedo_texture = source_textures.resolve(spec.sourceTexture)
				if material.albedo_texture == null or not SourceTextureImages.apply_sampling(material, spec.sourceTexture):
					get_tree().quit(1)
					return
			elif int(spec.texture) >= 0:
				material.albedo_texture = textures[int(spec.texture)]
			material.emission_energy_multiplier = spec.emissionIntensity
			if int(spec.emission) != 0:
				material.emission_enabled = true
				material.emission = Color.hex((int(spec.emission) << 8) | 0xff)
			materials.append(material)
		var nodes: Array[Node3D] = []
		for spec: Dictionary in data.nodes:
			var node: Node3D = MultiMeshInstance3D.new() if spec.has("instances") else MeshInstance3D.new() if spec.has("mesh") else Node3D.new()
			node.name = "n_%d" % int(spec.id)
			node.rotation_order = {"XYZ": EULER_ORDER_XYZ, "XZY": EULER_ORDER_XZY, "YXZ": EULER_ORDER_YXZ,
				"YZX": EULER_ORDER_YZX, "ZXY": EULER_ORDER_ZXY, "ZYX": EULER_ORDER_ZYX}[spec.get("rotationOrder", "XYZ")]
			node.set_meta("source_name", spec.name)
			if spec.has("helper"):
				if spec.helper.get("type") != "SkeletonHelper" or bool(spec.visible) or spec.helper.get("visualizationAvailable", true):
					push_error("Unsupported source rig-preview helper")
					get_tree().quit(1)
					return
				node.set_meta("source_helper", spec.helper.duplicate(true))
			if spec.has("effect"):
				node.set_meta("source_effect", spec.effect)
			if spec.has("trs"):
				node.set_meta("source_trs", spec.trs)
			for flag: String in spec.get("flags", {}):
				node.set_meta(flag, bool(spec.flags[flag]))
			if spec.has("outlineUniforms"):
				node.set_meta("source_outline_uniforms", spec.outlineUniforms.duplicate(true))
				node.set_meta("source_outline_frustum_culled", bool(spec.outlineFrustumCulled))
			var m: Array = spec.matrix
			node.transform = Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
			node.visible = spec.visible
			nodes.append(node)
			if int(spec.parent) >= 0:
				nodes[int(spec.parent)].add_child(node)
				node.owner = nodes[0]
			if spec.has("mesh"):
				var geometry := _mesh(data.meshes[int(spec.mesh)], spec.materials, data.materials, materials, spec.get("flags", {}).get("materialArray", false))
				if geometry == null:
					get_tree().quit(1)
					return
				node.set_meta("source_dissolve_slots", spec.materials.map(func(id): return bool(data.materials[int(id)].get("dissolve", false))))
				geometry.set_meta("source_geometry_id", int(spec.mesh))
				geometry.set_meta("source_indices", data.meshes[int(spec.mesh)].indices)
				geometry.set_meta("source_indexed", not data.meshes[int(spec.mesh)].indices.is_empty())
				if node is MultiMeshInstance3D:
					geometry.resource_local_to_scene = bodies
					var instances := MultiMesh.new()
					instances.resource_local_to_scene = true
					instances.transform_format = MultiMesh.TRANSFORM_3D
					instances.use_colors = spec.has("instanceColors")
					instances.mesh = geometry
					instances.instance_count = spec.instances.size()
					for index in range(spec.instances.size()):
						var matrix: Array = spec.instances[index]
						instances.set_instance_transform(index, Transform3D(Basis(Vector3(matrix[0], matrix[1], matrix[2]), Vector3(matrix[4], matrix[5], matrix[6]),
							Vector3(matrix[8], matrix[9], matrix[10])), Vector3(matrix[12], matrix[13], matrix[14])))
						if instances.use_colors:
							var color: Array = spec.instanceColors[index]
							instances.set_instance_color(index, Color(color[0], color[1], color[2]))
					if instances.buffer.size() != instances.instance_count * (16 if instances.use_colors else 12):
						push_error("Native renderer did not preserve the source MultiMesh buffer: " + character)
						get_tree().quit(1)
						return
					node.multimesh = instances
					if instances.use_colors:
						for surface in range(geometry.get_surface_count()):
							var material := geometry.surface_get_material(surface) as BaseMaterial3D
							if material != null:
								material.vertex_color_use_as_albedo = true
				else:
					var mesh_node := node as MeshInstance3D
					mesh_node.mesh = geometry
					for surface in range(geometry.get_surface_count()):
						var material: Material = geometry.surface_get_material(surface)
						if bodies or material is ShaderMaterial:
							# Direct node references let PackedScene remap scene-local materials.
							mesh_node.set_surface_override_material(surface, material)
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (civilians or bodies or companions or hazards or loot) and spec.get("castShadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if not _preserve_outline_shells(node, spec, data, materials):
				get_tree().quit(1)
				return
		nodes[0].set_meta("source_cel_data", cel_data)
		if bodies or first_person_shields:
			nodes[0].set_meta("source_materials", materials)
		var scene := PackedScene.new()
		var packing_error := scene.pack(nodes[0])
		if packing_error == OK:
			packing_error = await ResourcePublisher.publish(scene, "res://assets/%s/%s.scn" % [folder, character], get_tree())
		if packing_error != OK:
			nodes[0].free()
			push_error("Cannot pack source cockpit: " + character)
			get_tree().quit(1)
			return
		nodes[0].free()
		count += 1
	print("FIRST_PERSON_SHIELD_IMPORT_PASS profiles=" if first_person_shields else "WEAPON_EFFECT_IMPORT_PASS profiles=" if weapon_effects else "NPC_EFFECT_IMPORT_PASS profiles=" if npc_effects else "CIVILIAN_PART_IMPORT_PASS profiles=" if civilians else "BODY_IMPORT_PASS profiles=" if bodies else "LOOT_IMPORT_PASS profiles=" if loot else "HAZARD_IMPORT_PASS profiles=" if hazards else "COMPANION_IMPORT_PASS profiles=" if companions else "PROJECTILE_IMPORT_PASS profiles=" if projectiles else "COCKPIT_IMPORT_PASS characters=", count)
	get_tree().quit()

func _prepare_textures(data: Dictionary) -> bool:
	var domains := {}
	for id in range(data.materials.size()):
		var material: Dictionary = data.materials[id]
		if not material.has("sourceTexture"):
			continue
		var texture: Dictionary = material.sourceTexture
		var domain: Array = []
		if (texture.wrapS == "clamp") != (texture.wrapT == "clamp"):
			var channel := int(texture.get("channel", 0))
			var key := "uv" if channel == 0 else "uv" + str(channel)
			# Material switches can introduce a source material after the initial pose.
			# Bound the complete captured graph's UV channel and retain shared bindings.
			if not domains.has(key):
				var combined: Array = []
				for mesh: Dictionary in data.meshes:
					combined.append_array(mesh.get(key, []))
				domains[key] = combined
			domain = domains[key]
		material.sourceTexture = SourceTextureImages.prepare(texture, domain)
		if material.sourceTexture.is_empty():
			return false
	return true

func _preserve_outline_shells(node: Node3D, spec: Dictionary, data: Dictionary, materials: Array[Material]) -> bool:
	var shells: Array = []
	for outline: Dictionary in spec.get("outlines", []):
		var geometry := _mesh(data.meshes[int(outline.mesh)], [int(outline.material)], data.materials, materials)
		if geometry == null:
			push_error("Cannot preserve original outline geometry")
			return false
		geometry.set_meta("source_geometry_id", int(outline.mesh))
		shells.append({"geometry": geometry, "uniforms": outline.uniforms.duplicate(true),
			"matrix": outline.matrix.duplicate(), "same_geometry": bool(outline.sameGeometry),
			"geo_keep": bool(outline.geoKeep), "child_index": int(outline.childIndex),
			"visible": bool(outline.visible), "frustum_culled": bool(outline.frustumCulled)})
	if spec.has("outlines"):
		# Deferred shell geometry is data, so it cannot alter authored rig node IDs.
		node.set_meta("source_outline_shells", shells)
	return true

func _mesh(spec: Dictionary, material_ids: Array, descriptions: Array, materials: Array[Material], array_materials: bool = false) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in range(0, spec.position.size(), 3):
		vertices.append(Vector3(spec.position[i], spec.position[i + 1], spec.position[i + 2]))
	var normals := PackedVector3Array()
	for i in range(0, spec.normal.size(), 3):
		normals.append(Vector3(spec.normal[i], spec.normal[i + 1], spec.normal[i + 2]))
	var colors := PackedColorArray()
	var raw_colors: Array = spec.get("color", [])
	var color_size := int(spec.get("colorSize", 3))
	if color_size not in [3, 4] or raw_colors.size() % color_size != 0:
		push_error("Invalid original model vertex colour layout")
		return null
	for i in range(0, raw_colors.size(), color_size):
		colors.append(Color(raw_colors[i], raw_colors[i + 1], raw_colors[i + 2], raw_colors[i + 3] if color_size == 4 else 1.0))
	var raw: Array = spec.indices
	if raw.is_empty():
		raw = range(vertices.size())
	var groups: Array = spec.groups
	if groups.is_empty():
		groups = [{"start": 0, "count": raw.size(), "materialIndex": 0}]
	var mesh := ArrayMesh.new()
	mesh.set_meta("source_custom_attributes", spec.get("attributes", {}))
	for group: Dictionary in groups:
		if array_materials and int(group.materialIndex) >= material_ids.size():
			continue
		var material_id := int(material_ids[0 if material_ids.size() == 1 else int(group.materialIndex)])
		var desc: Dictionary = descriptions[material_id]
		var uv := PackedVector2Array()
		if desc.has("sourceTexture"):
			var channel := int(desc.sourceTexture.get("channel", 0))
			var coordinates: Array = spec.get("uv" if channel == 0 else "uv" + str(channel), [])
			if coordinates.size() != vertices.size() * 2:
				push_error("Missing original model material UV channel")
				return null
			for i in range(0, coordinates.size(), 2):
				var point := SourceTextureImages.coordinates(Vector2(coordinates[i], coordinates[i + 1]), desc.sourceTexture)
				if not point.is_finite():
					push_error("Non-finite original model texture coordinates")
					return null
				uv.append(point)
		else:
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
		if colors.size() == vertices.size() and desc.get("vertexColors", false):
			arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[material_id])
	return mesh
