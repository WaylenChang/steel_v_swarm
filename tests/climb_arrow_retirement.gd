extends "res://tests/run.gd"

const Helper = preload("res://tests/climb_suite.gd")
var held: Array[ClimbPresentation] = []
var resources: Array[WeakRef] = []

func _root(item: Dictionary) -> Node3D:
	var root := Helper.arrow_root(item)
	add_child(root)
	return root

func _bind(root: Node3D, item: Dictionary) -> ClimbPresentation:
	var view := ClimbPresentation.new()
	held.append(view)
	_check(view.configure(root, item.routes), "Bind captured arrow geometry and declared source route probes")
	for node: MultiMeshInstance3D in view.batches.values():
		resources.append(weakref(node.multimesh))
	return view

func _compare(view: ClimbPresentation, expected: Array) -> void:
	var actual_batches := []
	var expected_batches := []
	for batch in range(expected.size()):
		var key: String = ["up", "down"][batch]
		var mesh: MultiMesh = view.batches[key].multimesh
		var actual := []
		var original := []
		for index in range(mesh.instance_count):
			var frame := mesh.get_instance_transform(index)
			actual.append([frame.basis.x.x, frame.basis.x.y, frame.basis.x.z, 0,
				frame.basis.y.x, frame.basis.y.y, frame.basis.y.z, 0,
				frame.basis.z.x, frame.basis.z.y, frame.basis.z.z, 0,
				frame.origin.x, frame.origin.y, frame.origin.z, 1])
			original.append(expected[batch].slice(index * 16, index * 16 + 16))
		actual_batches.append(actual)
		expected_batches.append(original)
	Helper.compare_matrices(self, actual_batches, expected_batches)

func _closed(view: ClimbPresentation, item: Dictionary) -> void:
	var before := [view.age, view.revision, view.generation]
	var root := Node3D.new()
	_check(not view.configure(root, item.routes), "Retired arrow owners reject another binding")
	view.advance(100000)
	view.retire()
	_check(view.retired and not view.ready and view.source_root == null and view.batches.is_empty() and view.routes.is_empty(),
		"Arrow retirement releases private buffers, borrowed nodes and route references")
	_check(before == [view.age, view.revision, view.generation] and root.get_child_count() == 0,
		"Late arrow frames cannot resume phases or allocate observers")
	root.free()

func _programs(capture: Dictionary) -> void:
	for item: Dictionary in capture.cases:
		var root := _root(item)
		var saved := {}
		for node: MultiMeshInstance3D in root.get_children():
			saved[node.get_meta("source_climb_arrow")] = node.multimesh
		var view := _bind(root, item)
		_compare(view, item.initial)
		for frame: Dictionary in item.frames:
			view.advance(frame.delta)
			_compare(view, frame.matrices)
		for key: String in saved:
			var mesh: MultiMesh = saved[key]
			for index in range(mesh.instance_count):
				_check(mesh.get_instance_transform(index) == Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO),
					"Arrow animation preserves the saved scene's initially empty instance buffer")
		var routes: Array = item.routes.duplicate(true)
		root.free()
		_closed(view, item)
		_check(item.routes == routes, "Retirement never clears the caller's accepted route roster")

func _lifetimes(item: Dictionary) -> void:
	var root := _root(item)
	var view := _bind(root, item)
	view.advance(.125)
	var before := [view.age, view.generation, view.batches.up.multimesh]
	view.advance(NAN)
	view.advance(INF)
	view.advance(-1)
	_check(before == [view.age, view.generation, view.batches.up.multimesh], "Invalid arrow deltas do not reserve phases or replace buffers")
	remove_child(root)
	await get_tree().process_frame
	add_child(root)
	var copy := root.duplicate()
	add_child(copy)
	copy.free()
	_check(not view.retired and before == [view.age, view.generation, view.batches.up.multimesh],
		"Staging transfers and duplicate observers retain arrow phases and private instance buffers")
	var replacement := _root(item)
	_check(view.configure(replacement, item.routes), "Rebind arrows to a replacement root")
	for node: MultiMeshInstance3D in view.batches.values():
		resources.append(weakref(node.multimesh))
	root.free()

	_check(not view.retired and view.source_root == replacement, "Old root destruction cannot close replacement arrows")
	before = [view.age, view.revision]
	replacement.queue_free()
	view.advance(.25)
	_check(before == [view.age, view.revision], "Queued roots reject arrow phase reservations and instance writes")
	await get_tree().process_frame
	_closed(view, item)
	root = _root(item)
	view = ClimbPresentation.new()
	_check(view.configure(root, item.routes), "Bind a weakly observed arrow controller")
	var weak: WeakRef = weakref(view)
	view = null
	_check(weak.get_ref() == null, "An arrow root observer cannot retain its controller")
	await get_tree().process_frame
	_check(root.get_child_count() == 2, "Dropping the controller removes only its lifecycle observer")
	root.free()

func _admission(item: Dictionary) -> void:
	for replace in [false, true]:
		var root := _root(item)
		var next := _root(item)
		var view := ClimbPresentation.new()
		held.append(view)
		root.child_entered_tree.connect(func(_child: Node):
			if replace:
				_check(view.configure(next, item.routes), "A constructor callback can bind replacement arrows")
			else:
				view.retire(), CONNECT_ONE_SHOT)
		_check(not view.configure(root, item.routes), "Interrupted arrow admission rejects its obsolete constructor continuation")
		root.free()
		if replace:
			_check(view.ready and not view.retired and view.source_root == next and view.age == 0,
				"Replacement arrows retain their own constructor pose and binding")
			for node: MultiMeshInstance3D in view.batches.values():
				resources.append(weakref(node.multimesh))
		next.free()
		_closed(view, item)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Climb arrow buffers require a real renderer")
		get_tree().quit(1)
		return
	var capture: Dictionary = Content.read_json("res://tests/fixtures/climb_arrows.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.formatVersion == 1, "Load original climb presentation constructor programs")
	for path: String in capture.source.inputs:
		var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(source.sha256_text() == capture.source.inputs[path], "Current arrow producer: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs[path] == capture.source.sourceInputs[path], "Original arrow source matches imported provenance: " + path)
	for key: String in capture.rules:
		_check(Content.balance.movement.climb.arrows[key] == capture.rules[key], "Imported arrow constant retains original source value: " + key)
	if failures == 0:
		_programs(capture)
		await _lifetimes(capture.cases[1])
		_admission(capture.cases[1])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "Closed retained arrow owners release private native instance buffers")
	held.clear()
	print("CLIMB_ARROW_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
