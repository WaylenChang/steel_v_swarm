class_name AudioMusicState
extends RefCounted

signal command(value: Dictionary)

var rules: AudioRules
var preferences: AudioPreferences
var tracks: Dictionary = {}
var scene := ""
var initialized := false
var unlocked := false
var disposed := false
var low_power := false
var fading := false
var grace_scene: Variant = null
var fade_scene := ""
var fade_target: Variant = 0.0

func configure(metadata: Dictionary, profile: AudioPreferences) -> void:
	rules = AudioRules.new()
	rules.configure(metadata)
	preferences = profile
	preferences.changed.connect(_preference_changed)

func register_current() -> void:
	register_track(scene if not scene.is_empty() else "menu")

func register_track(name: String) -> void:
	if disposed or tracks.has(name):
		return
	var url: Variant = rules.music_url(name, low_power)
	if url == null:
		return
	tracks[name] = {"url": url, "ok": false, "volume": 0.0, "paused": true}
	command.emit({"op": "register", "name": name, "url": url})

func unlock() -> void:
	if disposed or unlocked:
		return
	# The source creates channel gains before applying the deferred scene intent.
	initialized = true
	apply_volume()
	register_current()
	unlocked = true
	if not scene.is_empty():
		_apply_scene(scene)

func set_scene(name: String) -> void:
	if disposed:
		return
	scene = name
	if unlocked:
		_apply_scene(name)

func ready(name: String) -> void:
	if disposed or not tracks.has(name):
		return
	tracks[name].ok = true
	if scene == name and unlocked:
		_apply_scene(name)

func failed(name: String) -> void:
	if not disposed and tracks.has(name):
		# Source error handling does not restart a completed grace timer.
		tracks[name].ok = false

func _apply_scene(name: String) -> void:
	register_track(name)
	fading = false
	grace_scene = null
	command.emit({"op": "cancel_timers"})
	fade_scene = name
	fade_target = preferences.bgm_volume
	if bool(tracks.get(name, {}).get("ok", false)) or not ControlPreferences.truthy(preferences.bgm_on):
		command.emit({"op": "fallback_stop"})
	else:
		grace_scene = name
		command.emit({"op": "grace", "seconds": rules.rules.musicTiming.graceSeconds})
	for key: String in tracks:
		if tracks[key].ok and key == name and ControlPreferences.truthy(preferences.bgm_on):
			tracks[key].paused = false
			command.emit({"op": "play", "name": key})
	fading = true
	command.emit({"op": "fade", "seconds": rules.rules.musicTiming.fadeSeconds})

func grace_elapsed() -> void:
	if disposed or grace_scene == null:
		return
	var name: String = grace_scene
	grace_scene = null
	if scene == name and not bool(tracks.get(name, {}).get("ok", false)) and ControlPreferences.truthy(preferences.bgm_on) and unlocked:
		command.emit({"op": "fallback_start", "name": name})

func fade_step() -> void:
	if disposed or not fading:
		return
	var done := true
	var timing: Dictionary = rules.rules.musicTiming
	for name: String in tracks:
		var track: Dictionary = tracks[name]
		if not track.ok:
			continue
		var want: Variant = fade_target if name == fade_scene and ControlPreferences.truthy(preferences.bgm_on) else 0.0
		var current: float = track.volume
		var numeric_want := VisualPreferences._number(want)
		var next := current + clampf(numeric_want - current, -float(timing.fadeStep), float(timing.fadeStep))
		_volume(name, clampf(next, 0, 1))
		if absf(next - numeric_want) > float(timing.fadeTolerance):
			done = false
		elif typeof(want) in [TYPE_INT, TYPE_FLOAT] and want == 0 and not track.paused:
			track.paused = true
			command.emit({"op": "pause", "name": name})
	if done:
		fading = false
		command.emit({"op": "fade_stop"})

func apply_volume() -> void:
	if disposed:
		return
	if initialized:
		command.emit({"op": "sfx_gain", "gain": VisualPreferences._number(preferences.sfx_volume) if ControlPreferences.truthy(preferences.sfx_on) else 0.0})
	for name: String in tracks:
		if tracks[name].ok:
			_volume(name, VisualPreferences._number(preferences.bgm_volume) if name == scene and ControlPreferences.truthy(preferences.bgm_on) else 0.0)
	command.emit({"op": "fallback_volume", "gain": VisualPreferences._number(preferences.bgm_volume) if ControlPreferences.truthy(preferences.bgm_on) else 0.0})

func _volume(name: String, gain: float) -> void:
	tracks[name].volume = gain
	command.emit({"op": "volume", "name": name, "gain": gain})

func _preference_changed(operation: String, _values: Dictionary) -> void:
	if disposed:
		return
	if operation in ["bgm_on", "master_on"] and unlocked and not scene.is_empty():
		_apply_scene(scene)
	else:
		apply_volume()

func dispose() -> void:
	if disposed:
		return
	disposed = true
	fading = false
	grace_scene = null
	if preferences.changed.is_connected(_preference_changed):
		preferences.changed.disconnect(_preference_changed)
	command.emit({"op": "cancel_timers"})
	command.emit({"op": "fallback_stop"})
	for name: String in tracks:
		tracks[name].paused = true
		command.emit({"op": "pause", "name": name})
