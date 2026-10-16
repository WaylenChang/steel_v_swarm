class_name MobileDamageGeometry
extends RefCounted

var stage := -1
var root: Node3D
var nodes: Array[GeometryInstance3D] = []
var collected := false
var initialized := false
var material_copies: Dictionary = {}
var colours: Dictionary = {}
var bindings: Array[Dictionary] = []
var scars: Array[Dictionary] = []

func apply(target: Node3D, kind: String, destination: int) -> bool:
	var profile: Dictionary = Content.balance.destruction.sceneProfiles.get(kind, {})
	if not profile.get("mobile", false) or destination == stage:
		return false
	if root != null and root != target:
		push_error("Mobile damage cannot be rebound to another model")
		return false
	root = target
	stage = destination
	if not collected:
		_collect(target)
		collected = true
	if destination == 0 and not initialized:
		return true
	if not initialized:
		_capture()
		initialized = true
	var strength := 0.0 if destination == 0 else .45 if destination == 1 else .8 if destination == 2 else 1.0
	var tint := Color.hex((int(profile.color) << 8) | 0xff).srgb_to_linear()
	for material: BaseMaterial3D in colours:
		var original: Color = colours[material]
		var colour := original.lerp(tint, strength * .65) * (1 - strength * .25)
		colour.a = original.a
		material.albedo_color = colour.linear_to_srgb()
	for scar: Dictionary in scars:
		if not is_instance_valid(scar.node):
			continue
		var node: MeshInstance3D = scar.node
		node.visible = destination > 0
		var material := node.material_override as BaseMaterial3D
		var colour := material.albedo_color
		colour.a = strength
		material.albedo_color = colour
		var vertices: PackedVector3Array = scar.vertices
		var count := floori(float(vertices.size()) / 4) * 2 if destination == 1 else vertices.size()
		scar.draw_count = count
		var mesh := ArrayMesh.new()
		if count > 0:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if count < vertices.size():
				arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(range(count))
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		node.mesh = mesh
	return true

func _collect(node: Node3D) -> void:
	if ViewOcclusion._geometry(node) != null and not node.get_meta("teamRing", false) and not node.get_meta("weatherScorch", false):
		nodes.append(node as GeometryInstance3D)
	for child: Node in node.get_children():
		if child is Node3D:
			_collect(child)

func _copy(material: Material) -> Material:
	if not material is BaseMaterial3D or not ViewOcclusion._opaque(material):
		return material
	if not material_copies.has(material):
		var copy := material.duplicate() as BaseMaterial3D
		material_copies[material] = copy
		colours[copy] = (material as BaseMaterial3D).albedo_color.srgb_to_linear()
	return material_copies[material]

func _capture() -> void:
	for candidate: Variant in nodes:
		if not is_instance_valid(candidate):
			continue
		var node := candidate as GeometryInstance3D
		if node.get_meta("noPaint", false) or node.get_meta("isOutline", false):
			continue
		var geometry := ViewOcclusion._geometry(node)
		var override := node.material_override
		var originals: Array[Material] = []
		var materials: Array[Material] = []
		for surface in range(geometry.get_surface_count()):
			originals.append(node.get_surface_override_material(surface) if node is MeshInstance3D else geometry.surface_get_material(surface))
			materials.append(_copy(ViewOcclusion._material(node, surface)))
		bindings.append({"node": node, "override": override, "originals": originals, "mesh": geometry})
		if override != null:
			node.material_override = _copy(override)
		elif node is MeshInstance3D:
			for surface in range(materials.size()):
				node.set_surface_override_material(surface, materials[surface])
		else:
			var batch := node as MultiMeshInstance3D
			var instances := batch.multimesh.duplicate() as MultiMesh
			instances.mesh = geometry.duplicate() as Mesh
			for surface in range(materials.size()):
				instances.mesh.surface_set_material(surface, materials[surface])
			batch.multimesh = instances
	for candidate: Variant in nodes:
		if scars.size() >= 12:
			break
		if not is_instance_valid(candidate):
			continue
		var node := candidate as GeometryInstance3D
		if node.get_meta("skinned", false) or node.get_meta("isOutline", false) or node.get_meta("noPaint", false) or node.get_meta("materialArray", false):
			continue
		if not ViewOcclusion._opaque(ViewOcclusion._material(node, 0)):
			continue
		_create_scar(node)

func _create_scar(owner: GeometryInstance3D) -> void:
	var geometry := ViewOcclusion._geometry(owner)
	var positions: PackedVector3Array = geometry.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = SceneDamageGeometry.source_indices(geometry).indices
	var stride := maxi(3, floori(float(indices.size()) / 36 / 3) * 3)
	var lines := PackedVector3Array()
	for offset in range(0, indices.size() - 2, stride):
		var a := positions[indices[offset]]
		var b := positions[indices[offset + 1]]
		var c := positions[indices[offset + 2]]
		var normal := SceneDamageGeometry._cross([b.x - a.x, b.y - a.y, b.z - a.z], [c.x - a.x, c.y - a.y, c.z - a.z])
		var length := sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
		var multiplier := .003 / length if length > 0 else .003
		var previous := Vector3.ZERO
		for weights: Array in [[.7, .2], [.4, .4], [.2, .3]]:
			var point := Vector3.ZERO
			for axis in range(3):
				point[axis] = float(a[axis]) * weights[0] + float(b[axis]) * weights[1] + float(c[axis]) * (1 - weights[0] - weights[1]) + normal[axis] * multiplier
			if weights != [.7, .2]:
				lines.append_array(PackedVector3Array([previous, point]))
			previous = point
	var scar := MeshInstance3D.new()
	scar.name = "MobileDamageScar"
	scar.set_meta("noOutline", true)
	scar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.hex(0x211b18ff)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	scar.material_override = material
	owner.add_child(scar)
	scars.append({"node": scar, "vertices": lines, "draw_count": lines.size()})

func release(forget_nodes: bool = false) -> void:
	if not initialized:
		if forget_nodes:
			stage = -1
			root = null
			collected = false
			nodes.clear()
		return
	for scar: Dictionary in scars:
		if is_instance_valid(scar.node):
			scar.node.free()
	for binding: Dictionary in bindings:
		if not is_instance_valid(binding.node):
			continue
		var node: GeometryInstance3D = binding.node
		node.material_override = binding.override
		if node is MeshInstance3D:
			for surface in range(binding.originals.size()):
				node.set_surface_override_material(surface, binding.originals[surface])
		else:
			(node as MultiMeshInstance3D).multimesh.mesh = binding.mesh
	stage = -1
	initialized = false
	if forget_nodes:
		root = null
		collected = false
		nodes.clear()
	scars.clear()
	bindings.clear()
	colours.clear()
	material_copies.clear()
