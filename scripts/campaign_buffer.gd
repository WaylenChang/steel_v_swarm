extends Node

signal progress(loaded: int, total: int, percent: int, name: String, ready: bool)

static var retained: Dictionary = {}

var pending: Dictionary = {}
var paths: Dictionary = {}
var completed: Dictionary = {}
var failed: Array[String] = []
var total := 0
var percent := 0
var complete := false
var started := false
var retired := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func begin(rules: Dictionary, font_path: String = "res://assets/fonts/NotoSansTC.ttf") -> void:
	if not _active() or started:
		return
	if not rules.modelAssets.is_empty():
		push_error("Campaign model buffering requires the accepted native manifest contract")
		return
	started = true
	total = rules.assets.size() + 2
	for path: String in rules.assets:
		paths[path] = "res://" + path
	paths.fonts = font_path
	paths.models = ""
	set_process(true)
	for path: String in rules.assets:
		if not _active():
			return
		_request(path, paths[path])
	if not _active():
		return
	_request("fonts", font_path)
	# The captured base MODEL_MANIFEST has no GLB jobs; its Promise still settles asynchronously.
	_settle.call_deferred("models", null, true)

func _request(name: String, path: String) -> void:
	if retained.has(path):
		_settle.call_deferred(name, retained[path], true)
		return
	if not ResourceLoader.exists(path):
		_settle.call_deferred(name, null, false)
		return
	if FileAccess.file_exists(path + ".import"):
		var metadata := ConfigFile.new()
		if metadata.load(path + ".import") != OK or not bool(metadata.get_value("remap", "valid", true)):
			_settle.call_deferred(name, null, false)
			return
	var error := ResourceLoader.load_threaded_request(path, "Resource", true, ResourceLoader.CACHE_MODE_REUSE)
	if error == OK:
		pending[name] = path
	else:
		_settle.call_deferred(name, null, false)

func _process(_delta: float) -> void:
	if not _active():
		return
	for name: String in pending.keys():
		if not _active():
			return
		var status := ResourceLoader.load_threaded_get_status(pending[name])
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var value: Resource
		if status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
			value = ResourceLoader.load_threaded_get(pending[name])
		_settle(name, value, status == ResourceLoader.THREAD_LOAD_LOADED and value != null)

func _settle(name: String, value: Resource, success: bool) -> void:
	if not _active() or not started or not paths.has(name) or completed.has(name):
		return
	pending.erase(name)
	completed[name] = true
	if not success:
		failed.append(name)
	elif value != null:
		retained[paths[name]] = value
	percent = mini(100, roundi(float(completed.size()) / total * 100))
	complete = completed.size() >= total
	if complete:
		set_process(false)
	# Original image/font/model failures finish their cache attempt and count toward readiness.
	progress.emit(completed.size(), total, percent, name, complete)

func _active() -> bool:
	if retired or not is_inside_tree():
		return false
	var owner: Node = self
	while owner != null:
		if owner.is_queued_for_deletion():
			return false
		owner = owner.get_parent()
	return true

func retire() -> void:
	if retired:
		return
	retired = true
	set_process(false)
	var requests := pending.values()
	pending.clear()
	paths.clear()
	for path: String in requests:
		preload("res://scripts/native_resource_drain.gd").finish(get_tree(), path)

func _exit_tree() -> void:
	retire()
