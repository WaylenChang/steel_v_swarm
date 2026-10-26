extends "res://tests/run.gd"

const PATH := "res://assets/worlds/__sol_loading__/held.sol_world"
const SECOND := "res://assets/worlds/__sol_loading__/second.sol_world"
const THIRD := "res://assets/worlds/__sol_loading__/third.sol_world"
const DecodeGuard = preload("res://tests/audio_loop_loading.gd").DecodeGuard

class HeldWorldLoader extends ResourceFormatLoader:
	var started := Semaphore.new()
	var release := Semaphore.new()
	var loads := 0
	var data: NativeWorldData
	var second: NativeWorldData
	var third: NativeWorldData
	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["sol_world"])
	func _handles_type(type: StringName) -> bool:
		return type == &"Resource"
	func _get_resource_type(_path: String) -> String:
		return "Resource"
	func _exists(path: String) -> bool:
		return path in [PATH, SECOND, THIRD]
	func _load(path: String, _original_path: String, _sub_threads: bool, _cache_mode: int) -> Variant:
		loads += 1
		started.post()
		release.wait()
		return data if path == PATH else second if path == SECOND else third

class ProbeResources extends RoomWorldResources:
	func path_for(settings: Dictionary) -> String:
		return settings.path

func _run() -> void:
	var decoder := HeldWorldLoader.new()
	decoder.data = NativeWorldData.new()
	decoder.data.scene = PackedScene.new()
	var root := Node3D.new()
	_check(decoder.data.scene.pack(root) == OK, "Prepare a loader-only resource probe, not a playable seasonal world")
	root.free()
	decoder.second = NativeWorldData.new()
	decoder.second.scene = decoder.data.scene
	decoder.third = NativeWorldData.new()
	decoder.third.scene = decoder.data.scene
	ResourceLoader.add_resource_format_loader(decoder, true)
	var retiring := ProbeResources.new()
	var survivor := ProbeResources.new()
	add_child(retiring)
	add_child(survivor)
	var events: Array = []
	retiring.progress.connect(func(_path, fraction): events.append(fraction))
	var ticket := retiring.request({"path": PATH})
	var deadline := Time.get_ticks_msec() + 5000
	var started := decoder.started.try_wait()
	while not started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		started = decoder.started.try_wait()
	_check(started, "The native room decoder is confirmed live and held on its worker")
	if not started:
		decoder.release.post()
		retiring.free()
		survivor.free()
		ResourceLoader.remove_resource_format_loader(decoder)
		_finish_retirement()
		return
	survivor.request({"path": PATH})
	var observed := events.size()
	remove_child(retiring)
	_check(retiring.generation > ticket and retiring.desired.is_empty() and retiring.resource == null and not retiring.loading,
		"Detachment invalidates readiness and returns the loader to an idle state")
	var guard := DecodeGuard.new()
	guard.release = decoder.release
	var thread := Thread.new()
	var thread_error := thread.start(guard.run)
	_check(thread_error == OK, "A separate guard can release native decode if retirement blocks")
	if thread_error != OK:
		decoder.release.post()
	else:
		get_tree().paused = true
		retiring.free()
		guard.returned.post()
		thread.wait_to_finish()
		_check(not guard.timed_out, "Room resource retirement returns before native decoding completes")
	deadline = Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(ResourceLoader.load_threaded_get_status(PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Every retired native request is collected after completion")
	_check(events.size() == observed and decoder.loads == 1, "Retired room resources publish no stale progress and do not duplicate decode")
	_check(survivor.resource == decoder.data and survivor.failure.is_empty(), "One retiring room consumer cannot consume another consumer's completion")
	get_tree().paused = false
	if ResourceLoader.load_threaded_get_status(PATH) in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		ResourceLoader.load_threaded_get(PATH)
	survivor.free()
	var cached := ProbeResources.new()
	add_child(cached)
	cached.progress.connect(func(_path, fraction):
		if fraction == 1:
			remove_child(cached))
	var cached_ticket := cached.request({"path": PATH})
	_check(not cached.is_inside_tree() and cached.resource == null and cached.generation > cached_ticket and not cached.loading,
		"Synchronous cached readiness listeners can detach the loader without retaining stale state")
	add_child(cached)
	cached.progress.disconnect(cached.progress.get_connections()[0].callable)
	var restored: NativeWorldData = await cached.prepare({"path": PATH})
	_check(restored == decoder.data and cached.loading == false, "Reattached room loaders require and accept a fresh request")
	cached.free()
	var callback_loader := ProbeResources.new()
	add_child(callback_loader)
	callback_loader.progress.connect(func(_path, _fraction): remove_child(callback_loader), CONNECT_ONE_SHOT)
	var callback_ticket := callback_loader.request({"path": SECOND})
	_check(callback_loader.generation > callback_ticket and not callback_loader.loading and callback_loader.resource == null,
		"An in-flight progress listener can detach the loader before the request call returns")
	callback_loader.free()
	deadline = Time.get_ticks_msec() + 5000
	var second_started := decoder.started.try_wait()
	while not second_started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		second_started = decoder.started.try_wait()
	_check(second_started, "The synchronously detached request still owns one confirmed native decoder")
	decoder.release.post()
	deadline = Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(SECOND) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(ResourceLoader.load_threaded_get_status(SECOND) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Synchronous progress retirement also drains its request after the node is freed")
	if ResourceLoader.load_threaded_get_status(SECOND) in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		ResourceLoader.load_threaded_get(SECOND)
	var early := ProbeResources.new()
	var completion := {"done": false, "value": decoder.data}
	early.tree_entered.connect(func(): _observe_prepare(early, THIRD, completion), CONNECT_ONE_SHOT)
	add_child(early)
	_check(early.loading and early.is_processing(), "A request started during tree_entered remains active after ready")
	deadline = Time.get_ticks_msec() + 5000
	var third_started := decoder.started.try_wait()
	while not third_started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		third_started = decoder.started.try_wait()
	_check(third_started and not completion.done, "A preparation waiter observes one confirmed held native request")
	var prebuild := RoomWorldPrebuild.new()
	prebuild.resources = early
	add_child(prebuild)
	prebuild.request({"path": THIRD, "map_index": 0, "team_size": 1, "swapped": false})
	early.free()
	await get_tree().process_frame
	_check(completion.done and completion.value == null, "A caller awaiting preparation receives cancellation when the loader is destroyed")
	_check(not prebuild.building and prebuild.failure == "Native world resource preparation was interrupted",
		"A surviving prebuild reports cancellation without accessing its destroyed resource loader")
	prebuild.free()
	decoder.release.post()
	deadline = Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(THIRD) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(ResourceLoader.load_threaded_get_status(THIRD) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Cancelled preparation does not orphan its native request")
	if ResourceLoader.load_threaded_get_status(THIRD) in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		ResourceLoader.load_threaded_get(THIRD)
	var outside := ProbeResources.new()
	outside.request({"path": PATH})
	_check(not outside.loading and not outside.failure.is_empty() and outside.desired.is_empty(), "Out-of-tree requests reject without reserving a native load")
	add_child(outside)
	var recovered: NativeWorldData = await outside.prepare({"path": PATH})
	_check(recovered == decoder.data, "An out-of-tree rejection cannot poison the next attached request")
	outside.free()
	var rebound := ProbeResources.new()
	add_child(rebound)
	var rebinding := {"done": false, "events": 0}
	rebound.progress.connect(func(_path, fraction):
		if fraction != 1:
			return
		rebinding.events += 1
		if not rebinding.done:
			rebinding.done = true
			remove_child(rebound)
			add_child(rebound)
			rebound.request({"path": PATH}))
	var rebound_ticket := rebound.request({"path": PATH})
	_check(rebinding.events == 2 and rebound.generation > rebound_ticket and rebound.resource == decoder.data,
		"A readiness listener can detach, reattach and replace the request without an extra stale completion")
	_check(not rebound.loading and rebound.is_inside_tree(), "The retired callback cannot overwrite its replacement loader state")
	rebound.free()
	ResourceLoader.remove_resource_format_loader(decoder)
	_finish_retirement()

func _finish_retirement() -> void:
	print("ROOM_RESOURCE_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _observe_prepare(loader: RoomWorldResources, path: String, completion: Dictionary) -> void:
	completion.value = await loader.prepare({"path": path})
	completion.done = true
