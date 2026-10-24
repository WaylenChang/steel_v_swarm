class_name RoomWorldResources
extends Node

signal progress(path: String, fraction: float)

class Preparation extends RefCounted:
	signal completed(value: NativeWorldData)

var desired := ""
var resource: NativeWorldData
var failure := ""
var loading := false
var failed_path := ""
var generation := 0
var pending_path := ""
var pending_ticket := 0
var previous_fraction := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(not pending_path.is_empty())

func path_for(settings: Dictionary) -> String:
	var map := Content.battle_map(settings)
	return WorldVariant.path(str(map.get("native_world", "")), settings.get("env", {}))

func request(settings: Dictionary, retry := false) -> int:
	var path := path_for(settings)
	if is_inside_tree() and not is_queued_for_deletion() and not path.is_empty() and path == desired and (not retry or failed_path != path):
		return generation
	generation += 1
	var ticket := generation
	desired = path
	resource = null
	failure = ""
	failed_path = ""
	if not is_inside_tree() or is_queued_for_deletion():
		desired = ""
		failure = "Room resource loader requires an active SceneTree"
		return ticket
	if path.is_empty():
		failure = "Missing original native world identity for room resource loading"
		return ticket
	if not loading:
		_load_desired()
	return ticket

func clear() -> void:
	generation += 1
	desired = ""
	resource = null
	failure = ""
	failed_path = ""
	# Godot cannot cancel a resource load. Drain its live request before releasing it.

func prepare(settings: Dictionary) -> Variant:
	var ticket := request(settings, true)
	if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion() or ticket != generation:
		return null
	if resource != null or not failure.is_empty():
		return resource
	var preparation := Preparation.new()
	_wait_prepared(weakref(self), get_tree(), ticket, preparation)
	return preparation.completed

static func _wait_prepared(reference: WeakRef, tree: SceneTree, ticket: int, preparation: Preparation) -> void:
	# Return the signal to its caller before delivering even an immediate cancellation.
	await tree.process_frame
	while true:
		var loader := reference.get_ref() as RoomWorldResources
		if loader == null or not loader.is_inside_tree() or loader.is_queued_for_deletion() or loader.generation != ticket:
			preparation.completed.emit(null)
			return
		if loader.resource != null or not loader.failure.is_empty():
			var result := loader.resource
			loader = null
			preparation.completed.emit(result)
			return
		loader = null
		await tree.process_frame

func _load_desired() -> void:
	loading = true
	while not desired.is_empty():
		var path := desired
		var ticket := generation
		var loaded: Resource
		var error := OK
		if not ResourceLoader.exists(path):
			error = ERR_FILE_NOT_FOUND
		elif ResourceLoader.has_cached(path):
			loaded = load(path)
		else:
			error = ResourceLoader.load_threaded_request(path, "Resource", true, ResourceLoader.CACHE_MODE_REUSE)
			if error == OK:
				pending_path = path
				pending_ticket = ticket
				previous_fraction = -1
				set_process(true)
				_process(0)
				return
		_settle(path, ticket, loaded, error)
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if not loading or not pending_path.is_empty():
			return
		if ticket == generation:
			break
	loading = false
	set_process(false)

func _process(_delta: float) -> void:
	if pending_path.is_empty() or is_queued_for_deletion():
		return
	var fraction: Array = []
	var status := ResourceLoader.load_threaded_get_status(pending_path, fraction)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if pending_ticket == generation and not fraction.is_empty() and float(fraction[0]) != previous_fraction:
			previous_fraction = float(fraction[0])
			progress.emit(pending_path, previous_fraction)
		return
	var path := pending_path
	var ticket := pending_ticket
	pending_path = ""
	var loaded: Resource
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		loaded = ResourceLoader.load_threaded_get(path)
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		ResourceLoader.load_threaded_get(path)
	_settle(path, ticket, loaded, OK if status == ResourceLoader.THREAD_LOAD_LOADED else ERR_CANT_OPEN)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not loading or not pending_path.is_empty():
		return
	if ticket != generation and not desired.is_empty():
		_load_desired()
	else:
		loading = false
		set_process(false)

func _settle(path: String, ticket: int, loaded: Resource, error: Error) -> void:
	if ticket != generation:
		return
	var candidate := loaded as NativeWorldData
	if error != OK or candidate == null or candidate.scene == null:
		failed_path = path
		failure = "Cannot preload original native world resource: " + path + " (" + error_string(error if error != OK else ERR_INVALID_DATA) + ")"
	else:
		resource = candidate
		progress.emit(path, 1.0)

func _exit_tree() -> void:
	clear()
	if not pending_path.is_empty():
		var path := pending_path
		pending_path = ""
		preload("res://scripts/native_resource_drain.gd").finish(get_tree(), path)
	loading = false
	set_process(false)
