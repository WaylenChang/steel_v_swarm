extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const ViewTests = preload("res://tests/view_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["viewOcclusion", "viewFade"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original TPS occlusion oracle: " + key)
			return
	for item: Dictionary in fixtures.viewOcclusion:
		var graph := build_graph(item.graph)
		var root: Node3D = graph.root
		h.add_child(root)
		var state := ViewOcclusion.new()
		for name: String in item.skipped:
			state.skip_mesh(graph.nodes[name])
		if not item.noRegistry:
			state.register_root(root)
		var owner: Node3D = graph.nodes[item.owner]
		var camera := ViewTests.frame(item.camera)
		if item.geometry != null:
			var bounds := ViewOcclusion.body_bounds(owner)
			h._check(not bounds.is_empty(), "Original visible/hidden body and descendant outline bounds are present")
			if not bounds.is_empty():
				var box: AABB = bounds.box
				h._check(box.position.distance_to(h._reference_vector(item.geometry.bounds[0])) < 0.00001
					and box.end.distance_to(h._reference_vector(item.geometry.bounds[1])) < 0.00001,
					"Original expandByObject bounds include descendants of eligible meshes")
				var targets := ViewOcclusion.targets(box, camera.basis, item.height)
				for index in range(targets.size()):
					h._check(targets[index].distance_to(h._reference_vector(item.geometry.targets[index])) < 0.00001,
						"Original nine TPS body samples retain camera-right order and actual-height floor")
		for step: Dictionary in item.steps:
			if step.get("move", false):
				shift(graph, 500, step.get("moveInstances", false))
			if step.get("return", false):
				shift(graph, -500, step.get("moveInstances", false))
			if step.get("unregister", false):
				state.unregister_root(graph.nodes["wall"])
			state.update(step.now, camera, owner, item.height, not step.get("dead", false))
			Helper.compare(h, capture(state, graph.base), step.result, "Original TPS triangle occlusion/fade/hold/release: " + item.name)
		state.dispose()
		root.free()
	for item: Dictionary in fixtures.viewFade:
		var mesh := MeshInstance3D.new()
		mesh.name = "direct fade"
		mesh.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color.a = .7
		mesh.material_override = material
		var state := ViewOcclusion.new()
		if item.initiallyCleared:
			state.clear()
		for step: Dictionary in item.steps:
			if step.get("hit", false):
				state.hit(mesh, step.now)
			else:
				state.advance(step.now)
			Helper.compare(h, capture(state, {"direct fade": {"mesh": mesh, "materials": [material]}}), step.result,
				"Original first-frame/null versus cleared clock, inclusive hold deadline and capped linear fade")
			if step.result.previous == null:
				h._check(is_nan(state.previous), "Uninitialized source fade clock remains absent until the first advance")
		state.dispose()
		mesh.free()
	multimesh_isolation(h, fixtures.viewOcclusion)

static func shift(graph: Dictionary, amount: float, instances: bool) -> void:
	if instances:
		var mesh := graph.nodes.wall as MultiMeshInstance3D
		for index in range(mesh.multimesh.instance_count):
			var frame := mesh.multimesh.get_instance_transform(index)
			frame.origin.x += amount
			mesh.multimesh.set_instance_transform(index, frame)
	else:
		graph.nodes.wall.position.x += amount
	graph.nodes["side wall"].position.x += amount
	graph.nodes["mixed wall"].position.x += amount

static func multimesh_isolation(h: Node, fixtures: Array) -> void:
	var matches: Array = fixtures.filter(func(item): return item.name == "mixed instanced wall")
	if matches.is_empty():
		h._check(false, "Regenerate original MultiMesh occlusion references")
		return
	var graph := build_graph(matches[0].graph)
	h.add_child(graph.root)
	var mesh := graph.nodes.wall as MultiMeshInstance3D
	var peer := MultiMeshInstance3D.new()
	graph.root.add_child(peer)
	peer.multimesh = mesh.multimesh
	var original := peer.multimesh.mesh
	var before := mesh.multimesh.get_instance_transform(0)
	var state := ViewOcclusion.new()
	state.hit(mesh, 10)
	state.advance(10)
	state.advance(10.02)
	h._check(peer.multimesh.mesh == original and mesh.multimesh != peer.multimesh,
		"Instanced view fades isolate shared geometry/materials and animated buffers")
	var frame := before
	frame.origin.y += 1
	mesh.multimesh.set_instance_transform(0, frame)
	h._check(peer.multimesh.get_instance_transform(0) == before, "Faded batch animation cannot mutate another actor's instance buffer")
	state.clear()
	h._check(mesh.multimesh.mesh == original and mesh.multimesh.get_instance_transform(0) == frame,
		"Restoring instanced materials preserves animation performed during the fade")
	state.hit(mesh, 11)
	var replacement := StandardMaterial3D.new()
	mesh.multimesh.mesh.surface_set_material(0, replacement)
	state.clear()
	h._check(mesh.multimesh.mesh.surface_get_material(0) == replacement,
		"Fade cleanup retains an external per-surface material replacement")
	state.dispose()
	graph.root.free()

static func build_graph(data: Dictionary) -> Dictionary:
	var materials: Array[StandardMaterial3D] = []
	for spec: Dictionary in data.materials:
		var material := StandardMaterial3D.new()
		material.albedo_color.a = spec.opacity
		material.set_meta("source_transparent", bool(spec.transparent))
		if spec.transparent:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials.append(material)
	var ordered: Array[Node3D] = []
	var nodes: Dictionary = {}
	var base: Dictionary = {}
	for spec: Dictionary in data.nodes:
		var node: Node3D = MultiMeshInstance3D.new() if spec.has("instances") else MeshInstance3D.new() if spec.has("materials") else Node3D.new()
		node.name = spec.name
		nodes[spec.name] = node
		ordered.append(node)
		node.transform = ViewTests.frame(spec.matrix)
		node.visible = spec.visible
		for flag: String in spec.flags:
			node.set_meta(flag, spec.flags[flag])
		if spec.has("materials"):
			var vertices := PackedVector3Array()
			for index in range(0, spec.position.size(), 3):
				vertices.append(Vector3(spec.position[index], spec.position[index + 1], spec.position[index + 2]))
			var source: Array = spec.indices if not spec.indices.is_empty() else range(vertices.size())
			var mesh := ArrayMesh.new()
			var groups: Array = spec.groups if spec.materials.size() > 1 else [{"start": 0, "count": source.size(), "materialIndex": 0}]
			var originals: Array = []
			for group: Dictionary in groups:
				var indices := PackedInt32Array()
				for index in range(int(group.start), int(group.start + group.count), 3):
					indices.append_array(PackedInt32Array([int(source[index]), int(source[index + 2]), int(source[index + 1])]))
				var arrays: Array = []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = vertices
				arrays[Mesh.ARRAY_INDEX] = indices
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var material: StandardMaterial3D = materials[int(spec.materials[int(group.materialIndex)])]
				mesh.surface_set_material(mesh.get_surface_count() - 1, material)
				originals.append(material)
			if node is MultiMeshInstance3D:
				var instances := MultiMesh.new()
				instances.transform_format = MultiMesh.TRANSFORM_3D
				instances.mesh = mesh
				instances.instance_count = spec.instances.size()
				for index in range(spec.instances.size()):
					instances.set_instance_transform(index, ViewTests.frame(spec.instances[index]))
				node.multimesh = instances
			else:
				(node as MeshInstance3D).mesh = mesh
			base[spec.name] = {"mesh": node, "materials": originals}
		if int(spec.parent) >= 0:
			ordered[int(spec.parent)].add_child(node)
	return {"root": ordered[0], "nodes": nodes, "base": base}

static func capture(state: ViewOcclusion, base: Dictionary) -> Dictionary:
	var registered: Array = []
	for value: WeakRef in state.registry.values():
		var mesh: GeometryInstance3D = value.get_ref()
		if is_instance_valid(mesh):
			registered.append(str(mesh.name))
	registered.sort()
	var fades: Array = []
	for value: Dictionary in state.fades.values():
		var mesh: GeometryInstance3D = value.mesh.get_ref()
		fades.append({"name": str(mesh.name), "k": value.k, "last_hit": value.last_hit})
	fades.sort_custom(func(first, second): return first.name < second.name)
	var materials: Array = []
	for name: String in base:
		var mesh: GeometryInstance3D = base[name].mesh
		var originals: Array = base[name].materials
		for surface in range(originals.size()):
			var material: BaseMaterial3D = ViewOcclusion._material(mesh, surface)
			materials.append({"name": name + (":" + str(surface) if originals.size() > 1 else ""), "alpha": material.albedo_color.a, "original": material == originals[surface],
				"transparent": material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "depth": material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED})
	materials.sort_custom(func(first, second): return first.name < second.name)
	return {"registered": registered, "next": state.next_scan, "previous": null if is_nan(state.previous) else state.previous, "fades": fades, "materials": materials}
