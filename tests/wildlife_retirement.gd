extends "res://tests/run.gd"

var held: Array[WildlifePresentation] = []
var resources: Array[WeakRef] = []

func _source(item: Dictionary) -> Dictionary:
	var limbs: Array = []
	for index in range(item.parts.size()):
		var part: Dictionary = item.parts[index]
		limbs.append({"mesh": index + 2, "pivot": part.p, "rest": [0, 0, 0, 1],
			"wing": part.get("wing", 0), "tail": part.get("tail", false), "leg": part.get("leg", 0)})
	var profile := {"low": false, "stride": 2, "states": [item.state], "bounds": item.bounds, "waterY": 0,
		"batches": [{"species": item.species, "body": 1, "limbs": limbs,
			"animals": [{"state": 0, "i": 0}, {"state": 0, "i": 1}, {"state": 0, "i": 2}]}]}
	return {"variants": [profile], "footprints": {"cell": 16, "feet": [], "grid": {}}}

func _root() -> Node3D:
	# Probe meshes are deliberate writer/lifetime inputs, not original animal geometry or a playable map.
	var root := Node3D.new()
	for id in range(1, 5):
		var node := MultiMeshInstance3D.new()
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = BoxMesh.new()
		node.multimesh.instance_count = 3
		for index in range(3):
			node.multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		node.set_meta("source_wildlife_mesh", id)
		root.add_child(node)
	add_child(root)
	return root

func _bind(root: Node3D, item: Dictionary, height: Callable = Callable()) -> WildlifePresentation:
	var view := WildlifePresentation.new()
	held.append(view)
	var probe := height if height.is_valid() else func(x: float, _z: float): return -4 if item.mode == "wet" else NAN if item.mode == "missing" and x > 0 else 10
	_check(view.configure(root, _source(item), false, probe,
		func(_x: float, _z: float): return 1 if item.mode == "wet" else 0,
		func(_x: float, _z: float): return false), "Bind controlled wildlife writer states to actual native instance buffers")
	for node: MultiMeshInstance3D in view.meshes.values():
		resources.append(weakref(node.multimesh))
	return view

func _closed(view: WildlifePresentation, item: Dictionary) -> void:
	var before := [view.revision, view.generation, view.frame]
	var root := Node3D.new()
	_check(not view.configure(root, _source(item), false, Callable(), Callable(), Callable()), "Retired wildlife owners reject later constructor work")
	view.advance(.25, 99999, {})
	view.write(99999, {})
	view.retire()
	_check(view.retired and not view.ready and view.source_root == null and view.states.is_empty()
		and view.meshes.is_empty() and view.batches.is_empty() and view.profile.is_empty(), "Wildlife retirement clears states, metadata and native mesh ownership")
	_check(view.habitat.retired and not view.habitat.probe.is_valid() and not view.habitat.code_at.is_valid()
		and not view.habitat.dry_at.is_valid() and not view.habitat.water_height.is_valid(), "Wildlife retirement releases all terrain callback targets")
	_check(before == [view.revision, view.generation, view.frame] and root.get_child_count() == 0,
		"Late wildlife calls cannot resume frames or allocate another root observer")
	root.free()

func _writers(capture: Dictionary) -> void:
	for item: Dictionary in capture.cases:
		var root := _root()
		var original: MultiMesh = root.get_child(0).multimesh
		var view := _bind(root, item)
		view.write(item.now, {"activity": item.activity})
		for id in range(1, 5):
			var mesh: MultiMesh = view.meshes[id].multimesh
			for index in range(3):
				var values: Array = item.matrices[id - 1].slice(index * 16, index * 16 + 16)
				var expected: Transform3D = preload("res://tests/quaternion_suite.gd").frame(values)
				var actual := mesh.get_instance_transform(index)
				_check(actual.origin.distance_to(expected.origin) < .003, "Original browser writer ground/water/bounce/invalid-state placement")
				for axis in range(3):
					_check(actual.basis[axis].distance_to(expected.basis[axis]) < .003,
						"Original browser wildlife heading, activity, wing/tail/leg writer order")
		_check(original.get_instance_transform(0) == Transform3D.IDENTITY, "Writer updates preserve the saved source instance buffer")
		root.free()
		_closed(view, item)

func _lifetimes(item: Dictionary) -> void:
	var root := _root()
	var view := _bind(root, item)
	var before := [view.frame, view.generation, view.states[0].time, view.meshes[1].multimesh]
	remove_child(root)
	await get_tree().process_frame
	add_child(root)
	var copy := root.duplicate()
	add_child(copy)
	copy.free()
	_check(not view.retired and before == [view.frame, view.generation, view.states[0].time, view.meshes[1].multimesh],
		"Wildlife tree transfers and duplicated observers preserve the original population, phase and private buffers")
	root.free()
	_closed(view, item)
	root = _root()
	view = WildlifePresentation.new()
	held.append(view)
	var weak: WeakRef = weakref(view)
	_check(view.configure(root, _source(item), false, func(_x: float, _z: float): return 10,
		func(_x: float, _z: float): return 0, func(_x: float, _z: float): return false), "Configure a weakly observed wildlife owner")
	held.erase(view)
	view = null
	_check(weak.get_ref() == null, "A source root's wildlife observer cannot retain its controller")
	await get_tree().process_frame
	_check(root.get_child_count() == 4, "Releasing a wildlife owner removes its obsolete observer while preserving borrowed meshes")
	root.free()
	root = _root()
	view = _bind(root, item)
	var replacement := _root()
	_check(view.configure(replacement, _source(item), false, func(_x: float, _z: float): return 10,
		func(_x: float, _z: float): return 0, func(_x: float, _z: float): return false), "Rebind wildlife to a new source root")
	for node: MultiMeshInstance3D in view.meshes.values():
		resources.append(weakref(node.multimesh))
	root.free()
	_check(not view.retired and view.ready and view.source_root == replacement, "A deleted old root cannot retire its replacement wildlife binding")
	replacement.free()
	_closed(view, item)
	root = _root()
	view = _bind(root, item)
	root.queue_free()
	var frame := view.frame
	view.advance(.25, 1, {})
	view.write(1, {})
	_check(view.frame == frame, "Queued wildlife roots reject frame reservations and instance writes")
	await get_tree().process_frame
	_closed(view, item)

func _callbacks(item: Dictionary) -> void:
	var starting_root := _root()
	var starting := WildlifePresentation.new()
	held.append(starting)
	starting_root.get_child(0).visibility_changed.connect(starting.retire, CONNECT_ONE_SHOT)
	_check(not starting.configure(starting_root, _source(item), false, func(_x: float, _z: float): return 10,
		func(_x: float, _z: float): return 0, func(_x: float, _z: float): return false)
		and starting.retired and starting_root.get_child(1).visible,
		"Visibility retirement interrupts wildlife initialization before later node or buffer changes")
	starting_root.free()
	_closed(starting, item)
	for replace in [false, true]:
		var root := _root()
		var view := _bind(root, item)
		var owner := view
		var next := _root()
		var old: MultiMesh = view.meshes[1].multimesh
		view.habitat.probe = func(_x: float, _z: float):
			if replace:
				_check(owner.configure(next, _source(item), false, func(_a: float, _b: float): return 10,
					func(_a: float, _b: float): return 0, func(_a: float, _b: float): return false), "Height callback can replace the root")
			else:
				owner.retire()
			return 10
		view.write(1.25, {})
		_check(old.get_instance_transform(0) == Transform3D.IDENTITY, "An interrupted height callback cannot resume stale instance writes")
		if replace:
			_check(view.ready and view.source_root == next, "Height replacement preserves the newly admitted root")
			view.retire()
		root.free()
		next.free()
		_closed(view, item)
	for kind in ["code", "water", "ground", "dry"]:
		var root := _root()
		var view := _bind(root, item)
		var owner := view
		var calls := {"later": 0}
		var habitat := view.habitat
		habitat.probe = func(_x: float, _z: float):
			if kind == "ground": owner.retire()
			else: calls.later += 1
			return -1
		habitat.code_at = func(_x: float, _z: float):
			if kind == "code": owner.retire()
			return 0
		habitat.water_height = func():
			if kind == "water": owner.retire()
			return 0
		habitat.dry_at = func(_x: float, _z: float):
			if kind == "dry": owner.retire()
			else: calls.later += 1
			return false
		_check(not habitat.valid_at(0, 0, 0) and view.retired, "Habitat cancellation seals each original query short-circuit boundary")
		_check(calls.later == (1 if kind == "dry" else 0), "Terrain cancellation cannot call later released query targets")
		root.free()
		_closed(view, item)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Wildlife writer/lifetime qualification requires a real renderer")
		get_tree().quit(1)
		return
	var capture: Dictionary = Content.read_json("res://tests/fixtures/wildlife_writer.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.formatVersion == 1, "Load scoped original wildlife writer oracle")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current wildlife writer producer: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs[path] == capture.source.sourceInputs[path], "Executed writer source agrees with imported provenance: " + path)
	if failures == 0:
		_writers(capture)
		var item: Dictionary = capture.cases[18]
		await _lifetimes(item)
		_callbacks(item)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "Closed wildlife owners release private native instance buffers after source-root destruction")
	held.clear()
	print("WILDLIFE_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
