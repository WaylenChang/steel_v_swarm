class_name AudioLoopPlayer
extends AudioStreamPlayer

signal loaded
signal load_failed(error: Error)

var pending_path := ""
var opened := false
var play_when_loaded := false
var retired := false

func open(url: String, destination: StringName) -> Error:
	if not _active():
		return ERR_UNCONFIGURED
	if opened:
		return ERR_ALREADY_IN_USE
	opened = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	bus = destination
	if not url.begins_with("audio/") or ".." in url:
		return _fail(ERR_INVALID_PARAMETER)
	var path := "res://assets/" + url
	var tree := get_tree()
	if not ResourceLoader.exists(path, "AudioStream"):
		return _fail(ERR_FILE_NOT_FOUND)
	if not _active():
		return ERR_UNCONFIGURED
	var error := ResourceLoader.load_threaded_request(path, "AudioStream")
	if error != OK:
		return _fail(error)
	if not _active():
		_drain_request(tree, path)
		return ERR_UNCONFIGURED
	pending_path = path
	return OK

func _process(_delta: float) -> void:
	if not _active() or pending_path.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := pending_path
	pending_path = ""
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_drain_request(get_tree(), path)
		_fail(ERR_FILE_CANT_READ)
		return
	var candidate := ResourceLoader.load_threaded_get(path) as AudioStream
	if not _active():
		return
	if not candidate is AudioStreamOggVorbis and not candidate is AudioStreamMP3:
		_fail(ERR_FILE_UNRECOGNIZED)
		return
	# Never change loop properties on an imported/shared resource.
	stream = candidate.duplicate() as AudioStream
	stream.set("loop", true)
	stream.set("loop_offset", 0.0)
	if play_when_loaded:
		play()
	loaded.emit()

func _fail(error: Error) -> Error:
	if _active():
		load_failed.emit(error)
	return error

func _active() -> bool:
	return not retired and is_inside_tree() and not is_queued_for_deletion()

static func _drain_request(tree: SceneTree, path: String) -> void:
	await preload("res://scripts/native_resource_drain.gd").finish(tree, path)

func retire() -> void:
	if retired:
		return
	retired = true
	stop()
	# Native threaded requests have no cancellation API; collect their results.
	if not pending_path.is_empty():
		var path := pending_path
		pending_path = ""
		_drain_request(get_tree(), path)
	stream = null

func _exit_tree() -> void:
	retire()
