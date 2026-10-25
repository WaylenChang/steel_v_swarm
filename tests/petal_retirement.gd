extends "res://tests/run.gd"

var held: Array[PetalPresentation] = []
var resources: Array[WeakRef] = []

func _source() -> Dictionary:
	# Explicit grounded probes isolate resource ownership and callback cancellation.
	return {"variants": [{"season": "spring", "low": false, "time": 7.5,
		"constants": {"DT_MAX": .25, "ASPECT": 1},
		"parts": [{"cx": 1, "cz": 2, "ox": .1, "oz": .2, "oy": 0, "y0": 3,
			"groundTime": 1, "a": .5, "ang": 0, "ax": 1, "ay": 0, "az": 0,
			"sz": 1, "tone": 0, "mi": 0}],
		"batches": [{"id": 1, "count": 1, "tone": 0, "priority": 1}]}]}

func _root() -> Node3D:
	var root := Node3D.new()
	var node := MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = QuadMesh.new()
	node.multimesh.instance_count = 1
	node.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	node.material_override = StandardMaterial3D.new()
	node.set_meta("source_petal_mesh", 1)
	root.add_child(node)
	add_child(root)
	return root

func _bind(root: Node3D) -> PetalPresentation:
	var view := PetalPresentation.new()
	held.append(view)
	_check(view.configure(root, _source(), "spring", false, func(_x: float, _z: float): return 4,
		func(_x: float, _z: float): return 0), "Admit a grounded petal ownership probe")
	resources.append(weakref(view.meshes[1].multimesh))
	resources.append(weakref(view.meshes[1].material_override))
	return view

func _closed(view: PetalPresentation) -> void:
	var before := [view.revision, view.generation, view.time]
	var root := Node3D.new()
	_check(not view.configure(root, _source(), "spring", false, Callable(), Callable()), "Closed petal owners reject reconfiguration")
	view.advance(.25, {})
	view.retire()
	_check(view.retired and not view.ready and view.source_root == null and view.profile.is_empty()
		and view.parts.is_empty() and view.meshes.is_empty() and view.motion.rules.is_empty(), "Petal retirement releases all state and resource maps")
	_check(not view.probe.is_valid() and not view.code_at.is_valid(), "Petal retirement releases both terrain query targets")
	_check(before == [view.revision, view.generation, view.time] and root.get_child_count() == 0,
		"Late petal commands cannot advance clocks or allocate observers")
	root.free()

func _lifetimes() -> void:
	var root := _root()
	var saved: MultiMesh = root.get_child(0).multimesh
	var material: Material = root.get_child(0).material_override
	var view := _bind(root)
	var before := [view.time, view.generation, view.meshes[1].multimesh, view.meshes[1].material_override]
	remove_child(root)
	await get_tree().process_frame
	add_child(root)
	var copy := root.duplicate()
	add_child(copy)
	copy.free()
	_check(not view.retired and before == [view.time, view.generation, view.meshes[1].multimesh, view.meshes[1].material_override],
		"Staging transfers and duplicate observers preserve the original petal phase and private resources")
	view.advance(.1, {})
	_check(view.time > 7.5 and saved.get_instance_transform(0) == Transform3D.IDENTITY
		and material.render_priority == 0, "Active petal writes preserve saved source buffers and material ordering")
	root.free()
	_closed(view)
	root = _root()
	view = _bind(root)
	var replacement := _root()
	_check(view.configure(replacement, _source(), "spring", false, func(_x: float, _z: float): return 4,
		func(_x: float, _z: float): return 0), "Rebind a live petal controller")
	resources.append(weakref(view.meshes[1].multimesh))
	resources.append(weakref(view.meshes[1].material_override))
	root.free()
	_check(not view.retired and view.ready and view.source_root == replacement, "Old root destruction cannot retire replacement petals")
	replacement.queue_free()
	var clock := view.time
	view.advance(.25, {})
	_check(view.time == clock, "Queued petal roots reject frame reservations")
	await get_tree().process_frame
	_closed(view)
	root = _root()
	view = _bind(root)
	var weak: WeakRef = weakref(view)
	held.erase(view)
	view = null
	_check(weak.get_ref() == null, "A petal root observer cannot retain its controller")
	await get_tree().process_frame
	_check(root.get_child_count() == 1, "Dropping a controller removes its observer while preserving borrowed visuals")
	root.free()

func _interruptions() -> void:
	for query in ["height", "code"]:
		for replace in [false, true]:
			var root := _root()
			var view := _bind(root)
			var owner := view
			var replacement := _root()
			var old: MultiMesh = view.meshes[1].multimesh
			var calls := {"code": 0}
			var interrupt := func():
				if replace:
					_check(owner.configure(replacement, _source(), "spring", false, func(_x: float, _z: float): return 8,
						func(_x: float, _z: float): return 0), "Terrain callbacks can publish a replacement petal binding")
				else:
					owner.retire()
			view.probe = func(_x: float, _z: float):
				if query == "height": interrupt.call()
				return 4
			view.code_at = func(_x: float, _z: float):
				calls.code += 1
				if query == "code": interrupt.call()
				return 0
			view.advance(.1, {})
			_check(old.get_instance_transform(0) == Transform3D.IDENTITY, "Cancelled landing queries cannot resume stale instance writes")
			_check(calls.code == (0 if query == "height" else 1), "Height cancellation stops the later ground-code query")
			if replace:
				_check(view.ready and view.source_root == replacement and view.time == 7.5 and not view.parts[0].has("restY"),
					"Interrupted writers cannot mutate the replacement clock or landing cache")
				view.retire()
			root.free()
			replacement.free()
			_closed(view)
	var nested_root := _root()
	var nested := _bind(nested_root)
	var nested_owner := nested
	nested.probe = func(_x: float, _z: float):
		nested_owner.probe = func(_a: float, _b: float): return 8
		nested_owner.advance(.1, {})
		return 4
	nested.advance(.1, {})
	_check(nested.parts[0].restY == 8 and absf(nested.time - 7.7) < .00001,
		"A nested frame retains its newer landing cache and clock")
	_check(absf(nested.meshes[1].multimesh.get_instance_transform(0).origin.y - 8.025) < .00001,
		"The interrupted outer frame cannot overwrite the nested frame's instance pose")
	nested_root.free()
	_closed(nested)
	var root := _root()
	var view := PetalPresentation.new()
	held.append(view)
	root.get_child(0).visibility_changed.connect(view.retire, CONNECT_ONE_SHOT)
	_check(not view.configure(root, _source(), "spring", false, Callable(), Callable()) and view.retired,
		"Visibility retirement stops constructor continuation before private resources are admitted")
	root.free()
	_closed(view)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Petal resource retirement requires a real renderer")
		get_tree().quit(1)
		return
	await _lifetimes()
	_interruptions()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "Closed retained petal owners release private native buffers and materials")
	held.clear()
	print("PETAL_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
