class_name AudioMusic
extends Node

signal fallback_requested(scene: String)
signal fallback_stopped
signal fallback_volume_changed(gain: float)
signal track_failed(scene: String, error: Error)

var state := AudioMusicState.new()
var buses: AudioBuses
var players: Dictionary = {}
var fade_timer: Timer
var grace_timer: Timer
var fallback: AudioMusicFallback
var configured := false
var retired := false
var resources := preload("res://scripts/audio_resource_snapshot.gd").new()

func configure(metadata: Dictionary, profile: AudioPreferences, routing: AudioBuses) -> Error:
	if retired or state.disposed or not is_inside_tree() or is_queued_for_deletion():
		return ERR_UNCONFIGURED
	if configured:
		return ERR_ALREADY_IN_USE
	if not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
		return ERR_UNCONFIGURED
	process_mode = Node.PROCESS_MODE_ALWAYS
	buses = routing
	buses.retiring.connect(_retire, CONNECT_ONE_SHOT)
	fade_timer = Timer.new()
	fade_timer.ignore_time_scale = true
	add_child(fade_timer)
	if retired or is_queued_for_deletion() or not is_inside_tree():
		return ERR_UNCONFIGURED
	fade_timer.timeout.connect(state.fade_step)
	grace_timer = Timer.new()
	grace_timer.one_shot = true
	grace_timer.ignore_time_scale = true
	add_child(grace_timer)
	if retired or is_queued_for_deletion() or not is_inside_tree():
		return ERR_UNCONFIGURED
	grace_timer.timeout.connect(state.grace_elapsed)
	state.configure(metadata, profile)
	fallback = AudioMusicFallback.new()
	fallback.resources = resources
	add_child(fallback)
	if retired or is_queued_for_deletion() or not is_inside_tree():
		return ERR_UNCONFIGURED
	var error := fallback.configure(metadata, profile, routing)
	if error != OK:
		return error
	fallback_requested.connect(fallback.start)
	fallback_stopped.connect(fallback.stop)
	fallback_volume_changed.connect(fallback.set_volume)
	fallback.unavailable.connect(func(mood: String, failure: Error) -> void: track_failed.emit(mood, failure))
	state.command.connect(_command)
	configured = true
	return OK

func _command(value: Dictionary) -> void:
	if not _active():
		return
	match value.op:
		"register": _register(value.name, value.url)
		"cancel_timers":
			fade_timer.stop()
			grace_timer.stop()
		"fade": fade_timer.start(float(value.seconds))
		"grace": grace_timer.start(float(value.seconds))
		"fade_stop": fade_timer.stop()
		"sfx_gain": buses.set_sfx_gain(float(value.gain))
		"fallback_start": fallback_requested.emit(value.name)
		"fallback_stop": fallback_stopped.emit()
		"fallback_volume": fallback_volume_changed.emit(float(value.gain))
		"volume":
			if players.has(value.name):
				var gain := float(value.gain)
				if not is_finite(gain) or gain < 0 or gain > 1:
					track_failed.emit(value.name, ERR_INVALID_PARAMETER)
					return
				players[value.name].volume_linear = gain
		"play":
			var player: AudioStreamPlayer = players[value.name]
			if not player.has_stream_playback():
				player.play()
			player.stream_paused = false
		"pause":
			if players.has(value.name):
				players[value.name].stream_paused = true

func _register(name: String, url: String) -> void:
	if not _active():
		return
	var player := _make_player()
	if not _active():
		player.free()
		return
	player.volume_linear = 0
	player.loaded.connect(state.ready.bind(name))
	player.load_failed.connect(func(error: Error) -> void: _fail(name, error))
	players[name] = player
	add_child(player)
	if not _active():
		return
	player.open(url, buses.bgm)

func _make_player() -> AudioLoopPlayer:
	return AudioLoopPlayer.new()

func _active() -> bool:
	return configured and not retired and not state.disposed and is_inside_tree() and not is_queued_for_deletion()

func _fail(name: String, error: Error) -> void:
	if not _active():
		return
	state.failed(name)
	track_failed.emit(name, error)

func _retire() -> void:
	if retired:
		return
	retired = true
	configured = false
	if is_instance_valid(buses) and buses.retiring.is_connected(_retire):
		buses.retiring.disconnect(_retire)
	if is_instance_valid(fade_timer):
		fade_timer.stop()
	if is_instance_valid(grace_timer):
		grace_timer.stop()
	state.dispose()
	if is_instance_valid(fallback):
		fallback._retire()
	for player: AudioLoopPlayer in players.values():
		player.retire()
	players.clear()

func _exit_tree() -> void:
	_retire()
