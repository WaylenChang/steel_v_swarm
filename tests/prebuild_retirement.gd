extends Node

const Fixtures = preload("res://tests/room_world_prebuild_suite.gd")

class HeldResources extends RoomWorldResources:
	signal released(data: NativeWorldData)
	func request(_settings: Dictionary, _retry := false) -> int:
		return generation
	func prepare(_settings: Dictionary) -> Variant:
		return released

class HeldWorld extends BattleWorld:
	signal released
	func build(map: Dictionary, _environment: Dictionary) -> void:
		bounds = map.bounds
		build_progress.emit()
		await released
		build_complete = true
		build_progress.emit()

class HeldPrebuild extends RoomWorldPrebuild:
	var created: HeldWorld
	func _create_world() -> BattleWorld:
		created = HeldWorld.new()
		return created

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		push_error("PREBUILD_RETIREMENT_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

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
	var world_id := cache.prepared.get_instance_id()
	var ticket := cache.generation
	remove_child(cache)
	_check(cache.generation > ticket and cache.selected.is_empty() and cache.prepared == null and not cache.building,
		"Detaching a ready prebuild immediately invalidates its ticket and retained world")
	await get_tree().process_frame
	_check(not is_instance_id_valid(world_id), "Detached prebuild releases its previously ready native world")
	add_child(cache)
	cache.request(settings)
	while cache.building:
		await get_tree().physics_frame
	_check(cache.prepared != null and cache.prepared.get_instance_id() != world_id,
		"Reattachment builds a fresh world instead of reusing retired readiness")
	cache.free()
	var destination := Node3D.new()
	add_child(destination)
	var held := HeldPrebuild.new()
	held.resources = resources
	add_child(held)
	held.request(settings)
	var completion := {"done": false, "world": null}
	_observe(held, settings, destination, completion)
	_check(held.building and not completion.done, "A pending transfer waits for the confirmed unfinished world")
	var pending_id := held.created.get_instance_id()
	ticket = held.generation
	remove_child(held)
	_check(held.generation > ticket and not held.building and held.building_viewport == null,
		"Detaching an unfinished prebuild invalidates and releases its staging viewport")
	await get_tree().process_frame
	_check(completion.done and completion.world == null, "A pending transfer receives cancellation after detachment")
	await get_tree().process_frame
	_check(not is_instance_id_valid(pending_id), "An unfinished retired world is freed without awaiting its completion signal")
	add_child(held)
	held.request(settings)
	held.created.released.emit()
	_check(held.prepared == held.created and not held.building,
		"A reattached prebuild can finish a fresh request after cancelling the old build")
	held.clear()
	completion = {"done": false, "world": null}
	_observe(held, settings, destination, completion)
	pending_id = held.created.get_instance_id()
	held.free()
	await get_tree().process_frame
	_check(completion.done and completion.world == null and not is_instance_id_valid(pending_id),
		"Destroying a building prebuild cancels its caller and releases the unfinished native tree")
	var loading := HeldResources.new()
	add_child(loading)
	cache = Fixtures.FixturePrebuild.new()
	cache.resources = loading
	add_child(cache)
	completion = {"done": false, "world": null}
	_observe(cache, settings, destination, completion)
	_check(cache.building and cache.creations == 0, "A prebuild can retire while waiting for its source resource")
	cache.free()
	await get_tree().process_frame
	_check(completion.done and completion.world == null, "Resource preparation cannot retain a destroyed prebuild or its transfer caller")
	loading.released.emit(NativeWorldData.new())
	loading.free()
	cache = Fixtures.FixturePrebuild.new()
	cache.resources = resources
	add_child(cache)
	var replacement := settings.duplicate(true)
	replacement.architecture_seed += 1
	cache.request(settings)
	while cache.building:
		await get_tree().physics_frame
	var original := cache.prepared
	var replace_on_transfer := func(_child: Node): cache.request(replacement)
	destination.child_entered_tree.connect(replace_on_transfer, CONNECT_ONE_SHOT)
	var transferred: BattleWorld = await cache.take(settings, destination)
	_check(transferred == original and original.get_parent() == destination,
		"Reparent callbacks cannot destroy the world already handed to its destination")
	_check(cache.building and cache.settings == replacement,
		"A destination callback's replacement request survives completion of the previous transfer")
	while cache.building:
		await get_tree().physics_frame
	_check(cache.prepared != null and cache.prepared.get_meta("room_prebuild_identity").architecture_seed == replacement.architecture_seed,
		"Replacement preparation completes with its own architecture identity")
	cache.clear()
	completion = {"done": false, "world": null}
	_observe(cache, settings, destination, completion)
	destination.free()
	await get_tree().process_frame
	_check(completion.done and completion.world == null, "Destroying the transfer destination cancels its waiter without consuming the prebuild")
	while cache.building:
		await get_tree().physics_frame
	_check(cache.prepared != null, "A lost transfer destination leaves the completed prebuild available to another destination")
	cache.free()
	cache = Fixtures.FixturePrebuild.new()
	cache.resources = resources
	cache.request(settings)
	_check(not cache.building and cache.selected.is_empty() and not cache.failure.is_empty(),
		"Out-of-tree prebuild requests reject without starting a native world")
	add_child(cache)
	cache.request(settings)
	while cache.building:
		await get_tree().physics_frame
	_check(cache.prepared != null and cache.failure.is_empty(), "An attached fresh request recovers from an out-of-tree rejection")
	destination = Node3D.new()
	add_child(destination)
	var free_on_transfer := func(_child: Node): cache.queue_free()
	destination.child_entered_tree.connect(free_on_transfer, CONNECT_ONE_SHOT)
	transferred = await cache.take(settings, destination)
	await get_tree().process_frame
	_check(not is_instance_valid(cache) and is_instance_valid(transferred) and transferred.get_parent() == destination,
		"A destination callback can retire the prebuild without losing its transferred world")
	destination.free()
	cache = Fixtures.FixturePrebuild.new()
	cache.resources = resources
	add_child(cache)
	var reference: WeakRef = weakref(cache)
	cache.child_entered_tree.connect(func(_child: Node): reference.get_ref().queue_free(), CONNECT_ONE_SHOT)
	cache.request(settings)
	_check(cache.is_queued_for_deletion() and cache.creations == 0, "Retirement during staging-viewport entry prevents subsequent world construction")
	await get_tree().process_frame
	_check(reference.get_ref() == null, "A retiring staging owner is released at the native deferred-free boundary")
	resources.free()
	print("PREBUILD_RETIREMENT assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _observe(cache: RoomWorldPrebuild, settings: Dictionary, destination: Node, completion: Dictionary) -> void:
	completion.world = await cache.take(settings, destination)
	completion.done = true
