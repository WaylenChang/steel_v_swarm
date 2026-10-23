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

func configure(metadata: Dictionary, profile: AudioPreferences, routing: AudioBuses) -> Error:
	if configured:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree() or routing == null or not routing.available():
		return ERR_UNCONFIGURED
	process_mode = Node.PROCESS_MODE_ALWAYS
	buses = routing
	fade_timer = Timer.new()
	fade_timer.ignore_time_scale = true
	add_child(fade_timer)
	fade_timer.timeout.connect(state.fade_step)
	grace_timer = Timer.new()
	grace_timer.one_shot = true
	grace_timer.ignore_time_scale = true
	add_child(grace_timer)
	grace_timer.timeout.connect(state.grace_elapsed)
	state.configure(metadata, profile)
	fallback = AudioMusicFallback.new()
	add_child(fallback)
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
	var player := AudioLoopPlayer.new()
	player.volume_linear = 0
	player.loaded.connect(state.ready.bind(name))
	player.load_failed.connect(func(error: Error) -> void: _fail(name, error))
	add_child(player)
	players[name] = player
	player.open(url, buses.bgm)

func _fail(name: String, error: Error) -> void:
	state.failed(name)
	track_failed.emit(name, error)

func _exit_tree() -> void:
	if not configured:
		return
	state.dispose()
	for player: AudioStreamPlayer in players.values():
		player.stop()
