extends "res://tests/fog_geometry.gd"

var held: Array[SkillFieldPresentation] = []
var released: Array[WeakRef] = []

func _state(id: int = 1) -> Dictionary:
	return {"id": id, "center": Vector2(12, -9), "radius": 35.0,
		"start": 10.0, "until": 18.0, "duration": 8.0, "side": "STEEL"}

func _owner() -> SkillFieldPresentation:
	var view := SkillFieldPresentation.new()
	add_child(view)
	held.append(view)
	view.child_entered_tree.connect(func(child: Node) -> void:
		released.append(weakref(child))
		_check(child.get_child_count() == 6, "Fog admission owns all original six layers before tree callbacks")
		for layer: MeshInstance3D in child.get_children():
			released.append(weakref(layer.mesh))
			released.append(weakref(layer.material_override)))
	return view

func _closed(view: SkillFieldPresentation) -> void:
	var before := [view.revision, view.get_child_count()]
	view.sync_fogs([_state()], "STEEL", 11)
	_check(view._fog(35, true) == null and view._ring(0, 35, 24) == null,
		"A retired owner rejects late direct geometry acquisition")
	view.retire()
	_check(view.retired and not view.visible and view.fog_nodes.is_empty() and view.meshes.is_empty(),
		"Retired fog owners release active roots and cached native geometry")
	_check(before == [view.revision, view.get_child_count()], "Late sync and repeated retirement cannot revive the owner")

func _lifetimes() -> void:
	var view := _owner()
	view.child_entered_tree.connect(func(child: Node) -> void:
		_check(view.fog_nodes.get(1) == child and child.position == Vector3(12, .5, -9),
			"Fog pose and membership are complete at native admission"))
	view.sync_fogs([_state()], "STEEL", 11)
	var root: Node3D = view.fog_nodes[1]
	view.retire()
	_check(not root.visible, "Retirement hides the old fog before deferred deletion")
	_closed(view)
	view = _owner()
	view.sync_fogs([_state(1), _state(2)], "STEEL", 11)
	var retiring := view
	view.fog_nodes[1].visibility_changed.connect(func() -> void:
		_check(retiring.retired and retiring.fog_nodes.is_empty() and retiring.meshes.is_empty(),
			"Retirement seals every cache and entry before the first visibility callback")
		retiring.sync_fogs([_state(9)], "STEEL", 11), CONNECT_ONE_SHOT)
	view.retire()
	_closed(view)
	view = _owner()
	var admitting := view
	view.child_entered_tree.connect(func(_child: Node) -> void: admitting.retire(), CONNECT_ONE_SHOT)
	view.sync_fogs([_state(1), _state(2)], "STEEL", 11)
	_check(view.get_child_count() == 1, "Admission retirement prevents every later allocation in the stale snapshot")
	_closed(view)
	view = _owner()
	var replacing := view
	view.child_entered_tree.connect(func(_child: Node) -> void:
		replacing.sync_fogs([_state(9)], "SWARM", 11), CONNECT_ONE_SHOT)
	view.sync_fogs([_state(1), _state(2)], "STEEL", 11)
	_check(view.fog_nodes.keys() == [9] and not view.fog_nodes[9].get_meta("ally"),
		"A reentrant admission snapshot supersedes the preceding roster and ally state")
	view.retire()
	_closed(view)
	for side in ["STEEL", "SWARM"]:
		view = _owner()
		view.sync_fogs([_state(1), _state(2)], "STEEL", 11)
		var removing := view
		var old: Node3D = view.fog_nodes[1]
		old.visibility_changed.connect(func() -> void:
			_check(not removing.fog_nodes.has(1), "Fog removal releases membership before invoking native callbacks")
			removing.sync_fogs([_state(9)], "STEEL", 11), CONNECT_ONE_SHOT)
		view.sync_fogs([] if side == "STEEL" else [_state(1), _state(2)], side, 11)
		_check(view.fog_nodes.keys() == [9] and not old.visible,
			"Reentrant removal or side replacement retains only the newer snapshot")
		view.retire()
		_closed(view)
	view = _owner()
	view.queue_free()
	view.sync_fogs([_state()], "STEEL", 11)
	_check(view.fog_nodes.is_empty() and view.meshes.is_empty() and view.revision == 0,
		"Queued owners reject allocation before exit")
	held.erase(view)
	view = _owner()
	view.sync_fogs([_state()], "STEEL", 11)
	remove_child(view)
	add_child(view)
	_closed(view)

func _world_lifetime() -> void:
	var world := BattleWorld.new()
	add_child(world)
	world.sync_fogs([_state()], "STEEL", 11)
	var old := world.skill_fields
	remove_child(world)
	_check(old.retired and old.fog_nodes.is_empty() and old.meshes.is_empty(), "World exit closes the fog owner")
	add_child(world)
	world.sync_fogs([_state()], "STEEL", 11)
	_check(world.skill_fields != old and not world.skill_fields.retired, "World reuse acquires a fresh fog owner")
	world.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fog retirement requires a real renderer")
		get_tree().quit(1)
		return
	var reference: Dictionary = Content.read_json("res://tests/fixtures/fog_geometry.json")
	_source(reference)
	if failures.is_empty():
		_cases(reference)
		_isolation()
		_lifetimes()
		_world_lifetime()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in released:
		_check(resource.get_ref() == null, "Closed fog owners release roots, private materials and mesh caches after native disposal")
	for view: SkillFieldPresentation in held:
		_check(view.get_child_count() == 0, "Retained terminal owners have no native child resources")
		view.free()
	held.clear()
	print("FOG_RETIREMENT_RESULT " + JSON.stringify({"assertions": assertions, "failures": failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
