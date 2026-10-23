class_name AudioLoopPlayer
extends AudioStreamPlayer

signal loaded
signal load_failed(error: Error)

var pending_path := ""
var opened := false
var play_when_loaded := false

func open(url: String, destination: StringName) -> Error:
	if opened:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	opened = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	bus = destination
	if not url.begins_with("audio/") or ".." in url:
		return _fail(ERR_INVALID_PARAMETER)
	var path := "res://assets/" + url
	if not ResourceLoader.exists(path, "AudioStream"):
		return _fail(ERR_FILE_NOT_FOUND)
	var error := ResourceLoader.load_threaded_request(path, "AudioStream")
	if error != OK:
		return _fail(error)
	pending_path = path
	return OK

func _process(_delta: float) -> void:
	if pending_path.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := pending_path
	pending_path = ""
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail(ERR_FILE_CANT_READ)
		return
	var candidate := ResourceLoader.load_threaded_get(path) as AudioStream
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
	load_failed.emit(error)
	return error

func _exit_tree() -> void:
	stop()
	# Native threaded requests have no cancellation API; collect their results.
	if not pending_path.is_empty():
		ResourceLoader.load_threaded_get(pending_path)
		pending_path = ""
