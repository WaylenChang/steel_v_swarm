class_name RoomWorldResources
extends Node

signal progress(path: String, fraction: float)

var desired := ""
var resource: NativeWorldData
var failure := ""
var loading := false
var failed_path := ""
var generation := 0

func path_for(settings: Dictionary) -> String:
	var map := Content.battle_map(settings)
	return WorldVariant.path(str(map.get("native_world", "")), settings.get("env", {}))

func request(settings: Dictionary, retry := false) -> int:
	var path := path_for(settings)
	if not path.is_empty() and path == desired and (not retry or failed_path != path):
		return generation
	generation += 1
	desired = path
	resource = null
	failure = ""
	failed_path = ""
	if path.is_empty():
		failure = "Missing original native world identity for room resource loading"
		return generation
	if not loading:
		_load_desired()
	return generation

func clear() -> void:
	generation += 1
	desired = ""
	resource = null
	failure = ""
	failed_path = ""
	# Godot cannot cancel a resource load. Drain its live request before releasing it.

func prepare(settings: Dictionary) -> NativeWorldData:
	var ticket := request(settings, true)
	while ticket == generation and resource == null and failure.is_empty():
		await get_tree().process_frame
	return resource if ticket == generation else null

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
				var fraction: Array = []
				var previous := -1.0
				var status := ResourceLoader.load_threaded_get_status(path, fraction)
				while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					if ticket == generation and not fraction.is_empty() and float(fraction[0]) != previous:
						previous = float(fraction[0])
						progress.emit(path, previous)
					await get_tree().process_frame
					status = ResourceLoader.load_threaded_get_status(path, fraction)
				if status == ResourceLoader.THREAD_LOAD_LOADED:
					loaded = ResourceLoader.load_threaded_get(path)
				else:
					if status == ResourceLoader.THREAD_LOAD_FAILED:
						ResourceLoader.load_threaded_get(path)
					error = ERR_CANT_OPEN
		if ticket != generation:
			continue
		var candidate := loaded as NativeWorldData
		if error != OK or candidate == null or candidate.scene == null:
			failed_path = path
			failure = "Cannot preload original native world resource: " + path + " (" + error_string(error if error != OK else ERR_INVALID_DATA) + ")"
		else:
			resource = candidate
			progress.emit(path, 1.0)
			if ticket != generation:
				continue
		break
	loading = false
