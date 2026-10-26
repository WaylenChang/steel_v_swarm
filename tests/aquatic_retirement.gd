extends "res://tests/run.gd"

var held: Array[AquaticPresentation] = []
var points: Array[AquaticDetritus] = []
var resources: Array[WeakRef] = []

func _source() -> Dictionary:
	# Explicit point/sphere/state probes qualify ownership, not source population or material pixels.
	var bubbles := []
	for swamp in [false, true]:
		bubbles.append({"surfaceY": 0, "floorY": -2, "y": -.01, "riseSpd": 1, "wobblePh": .2,
			"wobbleSpd": 1, "baseR": .1, "x": 1, "z": 2, "isSwamp": swamp})
	return {"systems": [
		{"kind": "bubble", "seed": 42, "draws": 0, "particles": bubbles,
			"batches": [{"id": 1, "role": "water", "count": 1}, {"id": 2, "role": "swamp", "count": 1}]},
		{"kind": "fish", "fishPerSchool": 2, "schools": [{"speed": 1, "radius": 3, "rotDir": 1,
			"phaseOff": .2, "cx": 1, "cz": 2, "swimDepth": -1}], "batches": [{"id": 3, "role": "fish", "count": 2}]},
		{"kind": "jelly", "jellies": [{"pulseSpd": 1, "pulsePh": .2, "x": 1, "z": 2, "baseY": -1,
			"driftR": .2, "scale": .5}], "batches": [{"id": 4, "role": "jelly", "count": 1}]},
		{"kind": "detritus", "batches": [{"id": 5, "count": 2}], "seeds": [.1, .2],
			"positions": [-1, -1, -1, 1, 0, 1], "colours": [.2, .3, .4, .5, .6, .7],
			"particles": [{"x": -1, "y": -1, "z": -1, "floorY": -2, "surfaceY": 0, "spd": 1},
				{"x": 1, "y": 0, "z": 1, "floorY": 0, "surfaceY": 0, "spd": 1}],
			"material": {"size": .1, "opacity": .3, "colour": [1, 1, 1], "vertexColors": true, "sizeAttenuation": true}}
	]}

func _root() -> Node3D:
	var root := Node3D.new()
	var source := _source()
	for system: Dictionary in source.systems:
		if system.kind == "detritus":
			root.add_child(AquaticDetritus.create_node(system))
			continue
		for batch: Dictionary in system.batches:
			var node := MultiMeshInstance3D.new()
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.mesh = SphereMesh.new()
			node.multimesh.instance_count = int(batch.count)
			for index in range(int(batch.count)):
				node.multimesh.set_instance_transform(index, Transform3D.IDENTITY)
			node.set_meta("source_aquatic_mesh", int(batch.id))
			root.add_child(node)
	add_child(root)
	return root

func _track(view: AquaticPresentation) -> void:
	for node: MultiMeshInstance3D in view.meshes.values():
		resources.append(weakref(node.multimesh))
	for system: Dictionary in view.systems:
		if system.kind == "detritus":
			points.append(system.motion)
			resources.append(weakref(system.motion.mesh))
		else:
			if system.kind == "bubble":
				resources.append(weakref(system.random))

func _bind(root: Node3D) -> AquaticPresentation:
	var view := AquaticPresentation.new()
	held.append(view)
	_check(view.configure(root, _source()), "Bind private buffers for all four aquatic system kinds")
	_track(view)
	return view

func _closed_points(motion: AquaticDetritus) -> void:
	var token := motion.generation
	motion.advance(.25, 100000)
	motion.retire()
	var node := MeshInstance3D.new()
	_check(not motion.configure(node, _source().systems[3]), "Closed point owners reject another native mesh binding")
	_check(motion.retired and not motion.ready and motion.source_node == null and motion.mesh == null
		and motion.particles.is_empty() and motion.positions.is_empty() and motion.seeds.is_empty(),
		"Point retirement releases native vertices, seeds, particles and node references")
	_check(token == motion.generation and node.get_child_count() == 0, "Late point commands are inert and cannot allocate observers")
	node.free()

func _closed(view: AquaticPresentation) -> void:
	var before := [view.generation, view.revision]
	var root := Node3D.new()
	_check(not view.configure(root, _source()), "Retired aquatic owners reject later constructor work")
	view.advance(.25, 100000)
	view.retire()
	_check(view.retired and not view.ready and view.source_root == null and view.systems.is_empty()
		and view.meshes.is_empty() and view.point_nodes.is_empty(), "Aquatic retirement releases systems and borrowed node maps")
	_check(before == [view.generation, view.revision] and root.get_child_count() == 0,
		"Late aquatic calls cannot reserve revisions or allocate observers")
	root.free()

func _lifetimes() -> void:
	var root := _root()
	var original: MultiMesh = root.get_child(0).multimesh
	var original_points: ArrayMesh = root.get_child(4).mesh
	var original_vertices: PackedVector3Array = original_points.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var view := _bind(root)
	var alias: Dictionary = view.systems[0]
	var random: SourceRng = alias.random
	var motion: AquaticDetritus = view.systems[3].motion
	view.advance(.2, 1)
	_check(alias.draws == 2 and motion.particles[0].y < -1, "Active owners still advance bubble resets and native point positions")
	_check(original.get_instance_transform(0) == Transform3D.IDENTITY and
		original_points.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original_vertices,
		"Aquatic frames preserve saved MultiMesh and point vertex buffers")
	var before := [view.generation, random.state, alias.draws, motion.positions.duplicate(), motion.mesh, view.meshes[1].multimesh]
	remove_child(root)
	await get_tree().process_frame
	add_child(root)
	var copy := root.duplicate()
	add_child(copy)
	copy.free()
	_check(not view.retired and not motion.retired and before == [view.generation, random.state, alias.draws,
		motion.positions, motion.mesh, view.meshes[1].multimesh], "Staging transfers and duplicate observers preserve populations, RNG and private buffers")
	root.free()
	_check(alias.is_empty(), "Root retirement seals aliased system dictionaries")
	var random_state := random.state
	_closed(view)
	_closed_points(motion)
	_check(random.state == random_state, "Late owner calls cannot consume the retired bubble RNG")
	root = _root()
	view = _bind(root)
	motion = view.systems[3].motion
	var replacement := _root()
	_check(view.configure(replacement, _source()), "Rebind all aquatic resources to a replacement root")
	_track(view)
	_closed_points(motion)
	root.free()
	_check(view.ready and not view.retired and view.source_root == replacement,
		"Old root and point observers cannot close replacement aquatic resources")
	var state := int(view.systems[0].random.state)
	var vertices: PackedFloat32Array = view.systems[3].motion.positions.duplicate()
	replacement.queue_free()
	view.advance(.25, 100)
	_check(state == int(view.systems[0].random.state) and vertices == view.systems[3].motion.positions,
		"Queued aquatic roots reject RNG draws, particle steps and native buffer writes")
	await get_tree().process_frame
	_closed(view)

func _point_lifetimes() -> void:
	var root := _root()
	var node: MeshInstance3D = root.get_child(4)
	var motion := AquaticDetritus.new()
	points.append(motion)
	_check(motion.configure(node, _source().systems[3]), "Bind an independently owned point controller")
	resources.append(weakref(motion.mesh))
	var before := [motion.generation, motion.mesh, motion.positions.duplicate()]
	root.remove_child(node)
	await get_tree().process_frame
	root.add_child(node)
	var copy := node.duplicate()
	root.add_child(copy)
	copy.free()
	_check(not motion.retired and before == [motion.generation, motion.mesh, motion.positions],
		"Independent point bindings survive detachment and duplicated leaf observers")
	node.queue_free()
	motion.advance(.25, 100)
	_check(before == [motion.generation, motion.mesh, motion.positions], "Queued point nodes reject private vertex updates")
	await get_tree().process_frame
	_closed_points(motion)
	root.free()
	root = _root()
	node = root.get_child(4)
	motion = AquaticDetritus.new()
	points.append(motion)
	_check(motion.configure(node, _source().systems[3]), "Admit a replaceable independent point binding")
	resources.append(weakref(motion.mesh))
	var next := AquaticDetritus.create_node(_source().systems[3])
	root.add_child(next)
	_check(motion.configure(next, _source().systems[3]), "Replace an active point binding without retiring the controller")
	resources.append(weakref(motion.mesh))
	node.free()
	_check(motion.ready and not motion.retired and motion.source_node == next,
		"An obsolete point observer cannot retire its replacement leaf")
	motion.advance(.2, 1)
	_check(motion.particles[0].y < -1, "Replacement point bindings retain live native updates")
	root.free()
	_closed_points(motion)
	root = _root()
	node = root.get_child(4)
	motion = AquaticDetritus.new()
	_check(motion.configure(node, _source().systems[3]), "Bind a weakly observed standalone point owner")
	var weak: WeakRef = weakref(motion)
	motion = null
	_check(weak.get_ref() == null, "Point nodes cannot retain their controllers through lifecycle observers")
	await get_tree().process_frame
	_check(node.get_child_count() == 0, "Dropping a point controller removes only its observer")
	root.free()
	root = _root()
	var view := AquaticPresentation.new()
	_check(view.configure(root, _source()), "Bind a weakly observed aquatic host")
	weak = weakref(view)
	view = null
	_check(weak.get_ref() == null, "A source root cannot retain its aquatic host")
	await get_tree().process_frame
	_check(root.get_child_count() == 5 and root.get_child(4).get_child_count() == 0,
		"Dropping an aquatic host releases its unretained point controller and both observers")
	root.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Aquatic native buffer retirement requires a real renderer")
		get_tree().quit(1)
		return
	await _lifetimes()
	await _point_lifetimes()
	for motion: AquaticDetritus in points:
		_closed_points(motion)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "Closed retained aquatic owners release private buffers and RNG resources")
	held.clear()
	points.clear()
	print("AQUATIC_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
