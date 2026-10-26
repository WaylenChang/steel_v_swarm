extends "res://tests/fire_clock.gd"

var held: Array[FirePresentation] = []
var released: Array[WeakRef] = []

func _fire(id: int = 7) -> Dictionary:
	var state := _state("fire")
	state.id = id
	return state

func _owner() -> FirePresentation:
	var view := FirePresentation.new()
	add_child(view)
	view.set_process(false)
	held.append(view)
	view.child_entered_tree.connect(func(child: Node) -> void:
		released.append(weakref(child))
		for entry: Dictionary in view.entries.values():
			if entry.root != child:
				continue
			for node: Node3D in entry.nodes.values():
				if node is MeshInstance3D:
					released.append(weakref(node.mesh))
					for surface in range(node.mesh.get_surface_count()):
						released.append(weakref(node.mesh.surface_get_material(surface)))
		var binding: SourceOutlineBinding = child.get_meta("source_outline_binding", null)
		if binding != null:
			for item: Dictionary in binding.bindings:
				released.append(weakref(item.material)))
	return view

func _closed(view: FirePresentation) -> void:
	var before := [view.clock, view.revision, view.get_child_count()]
	view.sync([_fire()], 99999, {"rain": 100})
	view._process(99)
	view.retire()
	_check(view.retired and view.entries.is_empty() and view.dynamics.is_empty()
		and not view.wall_clock.is_valid() and not view.visible,
		"Terminal fire owners release all records, weather and clocks")
	_check(before == [view.clock, view.revision, view.get_child_count()], "Late fire sync/frame commands cannot allocate or advance a closed owner")

func _lifetimes() -> void:
	var view := _owner()
	var admitting := view
	view.child_entered_tree.connect(func(child: Node) -> void:
		_check(admitting.entries.has(7) and admitting.entries[7].root == child
			and child.position == _fire().position and child.scale == Vector3.ONE * 2,
			"Fire pose, non-default scale and ownership are complete before native admission")
		var entry: Dictionary = admitting.entries[7]
		for item: Dictionary in entry.fx.flames + entry.fx.smoke:
			_check(entry.nodes.get("n_%d" % int(item.id)) is MeshInstance3D, "Every original fire FX node is ready at admission")
		admitting.retire(), CONNECT_ONE_SHOT)
	var enlarged := _fire(7)
	enlarged.scale *= 2
	view.sync([enlarged, _fire(8)], 5, {})
	_check(view.get_child_count() == 1, "Admission retirement stops later fire allocations")
	_closed(view)
	view = _owner()
	var weather := {"rain": 20}
	view.sync([_fire(7), _fire(8)], 5, weather)
	var retiring := view
	var records: Array = view.entries.values()
	records[0].root.visibility_changed.connect(func() -> void:
		_check(retiring.entries.is_empty() and retiring.dynamics.is_empty()
			and records[0].is_empty() and records[1].is_empty(), "Fire retirement seals every record and weather before visibility callbacks")
		retiring.sync([_fire(9)], 9, {}), CONNECT_ONE_SHOT)
	view.retire()
	_check(weather == {"rain": 20}, "Retirement cannot clear the caller's weather dictionary")
	_closed(view)
	view = _owner()
	var replacing := view
	view.child_entered_tree.connect(func(_child: Node) -> void:
		replacing.sync([_fire(9)], 9, {"rain": 100}), CONNECT_ONE_SHOT)
	view.sync([_fire(7), _fire(8)], 5, {})
	_check(view.entries.keys() == [9] and view.clock == 9 and view.dynamics == {"rain": 100},
		"Reentrant admission preserves only the new fire roster, clock and weather")
	view.retire()
	_closed(view)
	view = _owner()
	view.sync([_fire(7), _fire(8)], 5, {})
	var removing := view
	var old: Dictionary = view.entries[7]
	var root: Node3D = old.root
	root.visibility_changed.connect(func() -> void:
		_check(old.is_empty() and not removing.entries.has(7), "Fire removal releases its record before native callbacks")
		removing.sync([_fire(7)], 9, {}), CONNECT_ONE_SHOT)
	view.sync([], 5, {})
	_check(view.entries.keys() == [7] and view.entries[7].root != root and not root.visible,
		"A reused fire ID survives the interrupted old removal sweep")
	view.retire()
	_closed(view)
	for process in [false, true]:
		for replace in [false, true]:
			view = _owner()
			view.sync([_fire()], 5, {})
			var clock_owner := view
			view.wall_clock = func():
				clock_owner.wall_clock = Callable()
				if replace:
					clock_owner.sync([_fire(9)], 9, {"rain": 100})
				else:
					clock_owner.retire()
				return 123.0
			if process:
				view._process(0)
			else:
				view.sync([_fire(8)], 7, {})
			_check(view.clock == (9.0 if replace else 5.0), "Clock callback cancellation prevents stale fire clock writes")
			if replace:
				_check(view.entries.keys() == [9] and view.dynamics == {"rain": 100}, "Clock replacement cannot resume stale fire/weather synchronization")
				view.retire()
			_closed(view)
	for layer in ["flames", "smoke"]:
		view = _owner()
		view.sync([_fire()], 5, {})
		var entry: Dictionary = view.entries[7]
		var node: MeshInstance3D = entry.nodes["n_%d" % int(entry.fx[layer][0].id)]
		node.visible = false
		node.position = Vector3(50, 60, 70)
		var material := node.mesh.surface_get_material(0) as StandardMaterial3D
		material.albedo_color.a = .4
		node.visibility_changed.connect(view.retire, CONNECT_ONE_SHOT)
		view._process(0)
		_check(view.retired and entry.is_empty() and node.position == Vector3(50, 60, 70)
			and material.albedo_color.a == Color(1, 1, 1, .4).a, "Fire/smoke visibility retirement stops pose, opacity and depth continuations")
		_closed(view)
	view = _owner()
	view.sync([_fire()], 5, {})
	var frame_owner := view
	var record: Dictionary = view.entries[7]
	var flame: MeshInstance3D = record.nodes["n_%d" % int(record.fx.flames[0].id)]
	flame.visible = false
	flame.visibility_changed.connect(func() -> void:
		frame_owner.dynamics = {"wind": 100, "windDir": [0, 1]}
		frame_owner.clock = 8
		frame_owner._process(0), CONNECT_ONE_SHOT)
	view._process(0)
	_check(view.clock == 8 and absf(flame.quaternion.dot(SourceQuaternion.axis_angle(Vector3.RIGHT, .32))) > .999999,
		"A nested frame keeps its newer clock/wind pose after the old visibility continuation returns")
	view.retire()
	_closed(view)
	view = _owner()
	view.queue_free()
	view.sync([_fire()], 5, {})
	view._process(1)
	_check(view.entries.is_empty() and view.clock == 0 and view.revision == 0, "Queued fire owners reject late allocations and frame clocks")
	held.erase(view)

func _world_lifetime() -> void:
	var world := BattleWorld.new()
	add_child(world)
	world.sync_fires([_fire()], 5, {})
	var old := world.fire_visuals
	remove_child(world)
	_check(old.retired and old.entries.is_empty() and old.dynamics.is_empty(), "World exit closes the fire owner")
	add_child(world)
	world.sync_fires([_fire()], 9, {})
	_check(world.fire_visuals != old and not world.fire_visuals.retired, "World reuse acquires a fresh fire owner")
	world.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fire retirement qualification requires a real renderer")
		get_tree().quit(1)
		return
	_source()
	if failures.is_empty():
		_frames()
		_world_and_isolation()
		_lifetimes()
		_world_lifetime()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in released:
		_check(resource.get_ref() == null, "Private fire meshes, opacity/outline materials and roots release with their closed owner retained")
	for view: FirePresentation in held:
		_check(view.get_child_count() == 0, "Terminal fire owners retain no staged native resources")
		view.free()
	held.clear()
	print("FIRE_RETIREMENT_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
