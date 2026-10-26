extends "res://tests/mine_view.gd"

var held: Array[MinePresentation] = []
var released: Array[WeakRef] = []

func _state(id: int = 1) -> Dictionary:
	return {"id": id, "position": Vector3(12, .05, -8)}

func _owner() -> MinePresentation:
	var view := MinePresentation.new()
	add_child(view)
	held.append(view)
	view.child_entered_tree.connect(func(child: Node) -> void:
		released.append(weakref(child))
		released.append(weakref(child.mesh))
		for surface in range(child.mesh.get_surface_count()):
			released.append(weakref(child.mesh.surface_get_material(surface))))
	return view

func _closed(view: MinePresentation) -> void:
	var before := [view.revision, view.last_check, view.get_child_count()]
	view.sync([_state()])
	view.update_view(Vector3.ZERO, 99999)
	view.retire()
	_check(view.retired and view.entries.is_empty() and not view.wall_clock.is_valid() and not view.visible,
		"Terminal mine owners release entries and the clock provider")
	_check(before == [view.revision, view.last_check, view.get_child_count()], "Late calls cannot allocate or advance a retired mine owner")

func _lifetimes() -> void:
	var view := _owner()
	var admitting := view
	view.child_entered_tree.connect(func(child: Node) -> void:
		_check(admitting.entries.get(1) == child and child.position == _state().position,
			"Mine pose and private mesh ownership are complete before native admission")
		admitting.retire(), CONNECT_ONE_SHOT)
	view.sync([_state(1), _state(2)])
	_check(view.get_child_count() == 1, "Admission retirement prevents stale later mine allocations")
	_closed(view)
	view = _owner()
	view.sync([_state(1), _state(2)])
	var retiring := view
	var roots: Dictionary = view.entries
	view.entries[1].visible = true
	view.entries[1].visibility_changed.connect(func() -> void:
		_check(retiring.retired and retiring.entries.is_empty() and roots.is_empty(),
			"Retirement clears every mine entry before native visibility callbacks")
		retiring.sync([_state(9)]), CONNECT_ONE_SHOT)
	view.retire()
	_closed(view)
	view = _owner()
	var replacing := view
	view.child_entered_tree.connect(func(_child: Node) -> void:
		replacing.sync([_state(9)]), CONNECT_ONE_SHOT)
	view.sync([_state(1), _state(2)])
	_check(view.entries.keys() == [9], "Reentrant admission keeps only the newest mine roster")
	view.retire()
	_closed(view)
	view = _owner()
	view.sync([_state(1), _state(2)])
	var removing := view
	var old: MeshInstance3D = view.entries[1]
	old.visible = true
	old.visibility_changed.connect(func() -> void:
		_check(not removing.entries.has(1), "Mine removal releases membership before the visibility callback")
		removing.sync([_state(1)]), CONNECT_ONE_SHOT)
	view.sync([])
	_check(view.entries.keys() == [1] and view.entries[1] != old and not old.visible,
		"A reused mine ID survives the preceding interrupted removal sweep")
	view.retire()
	_closed(view)
	for replace in [false, true]:
		view = _owner()
		view.sync([_state()])
		var clock_owner := view
		view.wall_clock = func():
			if replace:
				clock_owner.sync([_state(9)])
			else:
				clock_owner.retire()
			return 123.0
		view.update_view(Vector3.ZERO, 5)
		_check(view.last_check == 0, "Reentrant clock cancellation cannot reserve a stale mine visibility check")
		if replace:
			_check(view.entries.keys() == [9], "Clock callback replacement preserves the new roster")
			view.retire()
		_closed(view)
	view = _owner()
	view.sync([_state(1), _state(2)])
	var visibility_owner := view
	var root: MeshInstance3D = view.entries[1]
	root.visible = false
	var material := root.mesh.surface_get_material(0) as StandardMaterial3D
	material.albedo_color.a = .4
	root.visibility_changed.connect(visibility_owner.retire, CONNECT_ONE_SHOT)
	view.update_view(_state().position, 5)
	_check(view.retired and material.albedo_color.a == Color(1, 1, 1, .4).a,
		"Visibility retirement stops the pending opacity write and later mine updates")
	_closed(view)
	view = _owner()
	view.sync([_state(1), _state(2)])
	var updating := view
	for node: MeshInstance3D in view.entries.values():
		node.visible = false
		node.mesh.surface_get_material(0).albedo_color.a = .4
	view.entries[1].visibility_changed.connect(func() -> void:
		updating.update_view(Vector3(100, 100, 100), 5.125), CONNECT_ONE_SHOT)
	view.update_view(_state().position, 5)
	_check(view.last_check == 5.125, "An eligible reentrant view update keeps its newer throttle reservation")
	for node: MeshInstance3D in view.entries.values():
		_check(not node.visible and node.mesh.surface_get_material(0).albedo_color.a == Color(1, 1, 1, .4).a,
			"An interrupted view update cannot overwrite newer hidden opacity or visibility")
	view.retire()
	_closed(view)
	view = _owner()
	var calls := {"count": 0}
	view.wall_clock = func():
		calls.count += 1
		return 5.0
	view.queue_free()
	view.sync([_state()])
	view.update_view(Vector3.ZERO, 5)
	_check(view.entries.is_empty() and view.last_check == 0 and calls.count == 0,
		"Queued mine owners reject calls before clock callbacks or allocation")
	held.erase(view)
	view = _owner()
	view.sync([_state()])
	remove_child(view)
	add_child(view)
	_closed(view)

func _world_lifetime() -> void:
	var world := AnchorWorld.new()
	add_child(world)
	var states := [{"id": 1, "x": 12.0, "z": -8.0}]
	world.sync_mines(states)
	var old := world.mine_visuals
	remove_child(world)
	_check(old.retired and old.entries.is_empty(), "World exit closes the mine owner")
	add_child(world)
	world.sync_mines(states)
	_check(world.mine_visuals != old and not world.mine_visuals.retired,
		"Reattached worlds acquire fresh mine presentation state")
	world.mine_visuals.free()
	world.update_mine_view(Vector3.ZERO, 5)
	world.sync_mines(states)
	_check(is_instance_valid(world.mine_visuals) and not world.mine_visuals.retired,
		"World view calls tolerate a released owner and the next roster reacquires it")
	world.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Mine retirement qualification requires a real renderer")
		get_tree().quit(1)
		return
	_source()
	if failures.is_empty():
		_program()
		_distance_edges()
		_world_clock()
		_lifetimes()
		_world_lifetime()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in released:
		_check(resource.get_ref() == null, "Private mine meshes/materials and roots release while their closed owner remains retained")
	for view: MinePresentation in held:
		_check(view.get_child_count() == 0, "Terminal mine owners retain no staged native children")
		view.free()
	held.clear()
	print("MINE_RETIREMENT_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
