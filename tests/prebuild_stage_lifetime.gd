extends Node

class Resources extends RoomWorldResources:
	func request(_settings: Dictionary, _retry := false) -> int:
		return generation
	func prepare(_settings: Dictionary) -> NativeWorldData:
		return NativeWorldData.new()

class HeldWorld extends BattleWorld:
	signal released
	var meter: Dictionary
	func _process(_delta: float) -> void:
		meter.ticks += 1
	func _physics_process(_delta: float) -> void:
		meter.ticks += 1
	func build(map: Dictionary, _environment: Dictionary) -> void:
		meter.builds += 1
		bounds = map.bounds
		build_progress.emit()
		await released
		build_complete = true
		build_progress.emit()

class Cache extends RoomWorldPrebuild:
	var meter := {"creations": 0, "builds": 0, "ticks": 0}
	var created: HeldWorld
	var on_create: Callable
	func _create_world() -> BattleWorld:
		meter.creations += 1
		var world := HeldWorld.new()
		world.meter = meter
		created = world
		var callback := on_create
		on_create = Callable()
		if callback.is_valid():
			callback.call()
		return world

var assertions := 0
var failures: Array[String] = []
var settings := {"map_index": 0, "team_size": 1, "swapped": false,
	"architecture_seed": 1, "env": {"season": "summer", "time": "day", "weather": "clear"}}

func _ready() -> void:
	get_tree().create_timer(15).timeout.connect(func():
		push_error("PREBUILD_STAGE_LIFETIME_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		failures.append(description)
		push_error(description)

func _frames(count: int = 3) -> void:
	for _index in range(count):
		await get_tree().process_frame

func _observe(cache: RoomWorldPrebuild, destination: Node, result: Dictionary) -> void:
	result.world = await cache.take(settings, destination)
	result.done = true

func _run() -> void:
	var resources := Resources.new()
	add_child(resources)
	for mode in ["viewport_entry", "world_entry", "viewport_pending", "world_pending"]:
		var cache := Cache.new()
		cache.resources = resources
		add_child(cache)
		var destination := Node3D.new()
		add_child(destination)
		if mode == "viewport_entry":
			cache.child_entered_tree.connect(func(child: Node): child.queue_free(), CONNECT_ONE_SHOT)
		elif mode == "world_entry":
			cache.child_entered_tree.connect(func(child: Node):
				child.child_entered_tree.connect(func(world: Node): world.queue_free(), CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)
		var result := {"done": false, "world": null}
		_observe(cache, destination, result)
		if mode == "viewport_pending":
			cache.building_viewport.queue_free()
		elif mode == "world_pending":
			cache.created.queue_free()
		await _frames()
		_check(result.done and result.world == null, mode + ": pending transfer resolves cancellation")
		_check(not cache.building and cache.prepared == null and not cache.failure.is_empty(),
			mode + ": lost staging cannot remain building or ready")
		_check(cache.meter.ticks == 0, mode + ": rejected staging never processes")
		if mode == "viewport_entry":
			_check(cache.meter.creations == 0, "Queued staging viewport rejects world allocation")
		if mode == "world_entry":
			_check(cache.meter.builds == 0, "Queued world rejects build admission")
		var retry := {"done": false, "world": null}
		_observe(cache, destination, retry)
		cache.created.released.emit()
		await _frames()
		_check(retry.done and is_instance_valid(retry.world) and retry.world.get_parent() == destination,
			mode + ": retry transfers a fresh completed tree")
		_check(cache.failure.is_empty() and not cache.building, mode + ": retry clears terminal staging failure")
		cache.free()
		destination.free()
		await _frames(1)
	for mode in ["world_ready", "viewport_ready", "completion_queue", "factory_replace", "loss_replace"]:
		await _replacement_case(resources, mode)
	for viewport_loss in [false, true]:
		await _rollback_loss(resources, viewport_loss)
	resources.free()
	print("PREBUILD_STAGE_LIFETIME assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _replacement_case(resources: Resources, mode: String) -> void:
	var cache := Cache.new()
	cache.resources = resources
	add_child(cache)
	var replacement := settings.duplicate(true)
	replacement.architecture_seed += 1
	var orphan := {"id": 0}
	if mode == "factory_replace":
		cache.on_create = func():
			orphan.id = cache.created.get_instance_id()
			cache.request(replacement)
	cache.request(settings)
	if mode == "completion_queue":
		cache.progress.connect(func():
			if cache.created.build_complete:
				cache.created.queue_free())
	if mode == "loss_replace":
		cache.changed.connect(func():
			if not cache.failure.is_empty():
				cache.request(replacement))
		cache.building_viewport.queue_free()
	else:
		cache.created.released.emit()
	if mode == "world_ready":
		cache.prepared.queue_free()
	elif mode == "viewport_ready":
		cache.prepared_viewport.queue_free()
	await _frames()
	if mode in ["world_ready", "viewport_ready", "completion_queue"]:
		_check(cache.prepared == null and not cache.failure.is_empty() and not cache.building,
			mode + ": retired readiness cannot be published or retained")
	else:
		if mode == "loss_replace":
			_check(cache.building and cache.settings == replacement, "Deferred loss notification admits a replacement outside tree notifications")
			cache.created.released.emit()
		_check(is_instance_valid(cache.prepared) and cache.prepared.get_meta("room_prebuild_identity").architecture_seed == replacement.architecture_seed,
			mode + ": replacement owns its completed staging tree")
		if mode == "factory_replace":
			_check(cache.meter.creations == 2 and cache.meter.builds == 1, "Factory replacement never builds the superseded world")
			_check(not is_instance_id_valid(orphan.id), "Superseded factory output is released before native admission")
	cache.free()
	await _frames(1)

func _rollback_loss(resources: Resources, viewport_loss: bool) -> void:
	var cache := Cache.new()
	cache.resources = resources
	add_child(cache)
	cache.request(settings)
	cache.created.released.emit()
	var world := cache.prepared
	for _attempt in range(2):
		var destination := Node3D.new()
		add_child(destination)
		destination.child_entered_tree.connect(func(_child: Node): destination.queue_free(), CONNECT_ONE_SHOT)
		var result: BattleWorld = await cache.take(settings, destination)
		_check(result == null and cache.prepared == world, "Cancelled transfer restores the same staged world")
		await _frames(1)
	if viewport_loss:
		cache.prepared_viewport.queue_free()
	else:
		cache.prepared.queue_free()
	await _frames()
	_check(cache.prepared == null and not cache.failure.is_empty() and not cache.building,
		"Rollback generation still observes staging loss: viewport=" + str(viewport_loss))
	cache.free()
	await _frames(1)
