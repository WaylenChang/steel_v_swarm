extends Node

const Fixtures = preload("res://tests/room_world_prebuild_suite.gd")

var assertions := 0
var failures: Array[String] = []

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(func():
		push_error("PREBUILD_TRANSFER_CANCELLATION_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	var resources := Fixtures.FixtureResources.new()
	var cache := Fixtures.FixturePrebuild.new()
	cache.resources = resources
	add_child(resources)
	add_child(cache)
	var settings := {"map_index": 0, "team_size": 1, "swapped": false,
		"architecture_seed": 1, "env": {"season": "summer", "time": "day", "weather": "clear"}}
	cache.request(settings)
	while cache.building:
		await get_tree().physics_frame
	var original := cache.prepared
	var original_id := original.get_instance_id()
	var viewport := cache.prepared_viewport
	var destination := Node3D.new()
	add_child(destination)
	destination.child_entered_tree.connect(func(_child: Node): destination.queue_free(), CONNECT_ONE_SHOT)
	var transferred: BattleWorld = await cache.take(settings, destination)
	_check(transferred == null, "A destination queued during reparenting cancels its transfer")
	_check(cache.prepared == original and cache.prepared_viewport == viewport,
		"A cancelled native transfer returns the same ready tree to its staging owner")
	await get_tree().process_frame
	_check(is_instance_id_valid(original_id), "Destination deletion cannot destroy the reclaimed prebuild")
	if is_instance_valid(original):
		_check(original.get_parent() == viewport and original.process_mode == Node.PROCESS_MODE_DISABLED,
			"Cancelled transfers remain isolated and cannot activate world processing")
		_check(original.get("process_ticks") == 0 and original.get("physics_ticks") == 0,
			"Rollback never admits a processing or physics tick in the rejected destination")
		var next := Node3D.new()
		add_child(next)
		var reused: BattleWorld = await cache.take(settings, next)
		_check(reused == original and cache.creations == 1, "Another destination can consume the reclaimed tree without rebuilding")
		next.free()
	cache.free()
	await _detached_destination(resources, settings)
	for mode in ["entry_request", "entry_retire", "entry_clear", "rollback_ready", "rollback_entry"]:
		await _replacement(resources, settings, mode)
	resources.free()
	print("PREBUILD_TRANSFER_CANCELLATION assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _detached_destination(resources: RoomWorldResources, settings: Dictionary) -> void:
	var cache := Fixtures.FixturePrebuild.new()
	cache.resources = resources
	add_child(cache)
	cache.request(settings)
	while cache.building:
		await get_tree().physics_frame
	var original := cache.prepared
	var viewport := cache.prepared_viewport
	var destination := Node3D.new()
	add_child(destination)
	# Detach before destination entry; removing an ancestor during child entry violates native tree notifications.
	viewport.child_exiting_tree.connect(func(_child: Node): remove_child(destination), CONNECT_ONE_SHOT)
	var result: BattleWorld = await cache.take(settings, destination)
	_check(result == null and not destination.is_inside_tree(), "Destination detachment during source exit rejects admission")
	_check(cache.prepared == original and original.get_parent() == viewport and original.process_mode == Node.PROCESS_MODE_DISABLED,
		"A detached destination returns its unactivated world to staging")
	destination.free()
	var next := Node3D.new()
	add_child(next)
	result = await cache.take(settings, next)
	_check(result == original and cache.creations == 1, "A detached-destination rollback preserves reusable readiness")
	next.free()
	cache.free()

func _replacement(resources: RoomWorldResources, settings: Dictionary, mode: String) -> void:
	var cache := Fixtures.FixturePrebuild.new()
	cache.resources = resources
	add_child(cache)
	cache.request(settings)
	while cache.building:
		await get_tree().physics_frame
	var original := cache.prepared
	var original_id := original.get_instance_id()
	var viewport := cache.prepared_viewport
	var replacement := settings.duplicate(true)
	replacement.architecture_seed += 1
	var destination := Node3D.new()
	add_child(destination)
	if mode == "rollback_ready":
		cache.changed.connect(func():
			if is_instance_valid(cache.prepared) and cache.prepared.get_instance_id() == original_id:
				cache.request(replacement))
	elif mode == "rollback_entry":
		viewport.child_entered_tree.connect(func(_child: Node): cache.request(replacement), CONNECT_ONE_SHOT)
	destination.child_entered_tree.connect(func(_child: Node):
		destination.queue_free()
		if mode == "entry_request": cache.request(replacement)
		elif mode == "entry_retire": cache.queue_free()
		elif mode == "entry_clear": cache.clear(), CONNECT_ONE_SHOT)
	var result: BattleWorld = await cache.take(settings, destination)
	_check(result == null, "Reentrant destination loss always resolves the old transfer as cancellation: " + mode)
	await get_tree().process_frame
	_check(not is_instance_id_valid(original_id), "A superseded cancelled transfer releases its obsolete tree: " + mode)
	if mode == "entry_retire":
		_check(not is_instance_valid(cache), "Prebuild retirement during rejected transfer releases the cache")
		return
	if mode == "entry_clear":
		_check(cache.prepared == null and cache.selected.is_empty() and not cache.building,
			"An explicit clear during failed transfer cannot resurrect the old readiness")
	else:
		_check(cache.settings == replacement, "A callback's fresh request survives rollback completion: " + mode)
		while cache.building:
			await get_tree().physics_frame
		_check(cache.prepared != null and cache.prepared.get_meta("room_prebuild_identity").architecture_seed == replacement.architecture_seed
			and cache.creations == 2, "Replacement preparation retains its own identity and one build: " + mode)
	cache.free()
