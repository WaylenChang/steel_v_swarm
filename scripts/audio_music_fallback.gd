class_name AudioMusicFallback
extends Node

signal unavailable(mood: String, error: Error)

var metadata: Dictionary = {}
var preferences: AudioPreferences
var buses: AudioBuses
var clips: Dictionary = {}
var voices: Array[Dictionary] = []
var current: Dictionary = {}
var configured := false

func configure(rules: Dictionary, profile: AudioPreferences, routing: AudioBuses) -> Error:
	if configured:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree() or routing == null or not routing.available():
		return ERR_UNCONFIGURED
	metadata = rules
	preferences = profile
	buses = routing
	process_mode = Node.PROCESS_MODE_ALWAYS
	configured = true
	return OK

func start(mood: String) -> void:
	if not configured or not buses.available():
		return
	if not current.is_empty() and current.mood == mood:
		return
	var now := _now()
	_stop(now)
	var arrangement := "battle" if mood == "battle" else "menu"
	var clip := _clip(arrangement)
	if clip == null:
		unavailable.emit(mood, ERR_UNAVAILABLE)
		return
	var volume := VisualPreferences._number(preferences.bgm_volume)
	if not is_finite(volume):
		unavailable.emit(mood, ERR_INVALID_PARAMETER)
		return
	var envelope := AudioMusicEnvelope.new()
	envelope.configure(metadata, AudioServer.get_mix_rate())
	var start_time := _now()
	envelope.start(start_time, volume, ControlPreferences.truthy(preferences.bgm_on))
	var player := AudioStreamPlayer.new()
	player.stream = clip.centered
	player.bus = buses.bgm
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.volume_linear = clip.centered_gain * envelope.value_at(start_time)
	add_child(player)
	current = {"mood": mood, "player": player, "envelope": envelope, "gain": clip.centered_gain, "retire_wall": INF}
	voices.append(current)
	player.play()

func stop() -> void:
	if configured:
		_stop(_now())

func _stop(now: float) -> void:
	if current.is_empty():
		return
	current.envelope.release(now)
	current.retire_wall = Time.get_ticks_usec() / 1000000.0 + float(metadata.proceduralMusic.retirementSeconds)
	current = {}

func set_volume(gain: float) -> void:
	if not configured or current.is_empty():
		return
	if not is_finite(gain):
		unavailable.emit(current.mood, ERR_INVALID_PARAMETER)
		return
	current.envelope.set_volume(_now(), gain)

func _process(_delta: float) -> void:
	if not configured:
		return
	var now := _now()
	for index in range(voices.size() - 1, -1, -1):
		var voice: Dictionary = voices[index]
		var envelope: AudioMusicEnvelope = voice.envelope
		if Time.get_ticks_usec() / 1000000.0 >= float(voice.retire_wall):
			envelope.disconnect_output()
			voice.player.stop()
			voice.player.queue_free()
			voices.remove_at(index)
			continue
		voice.player.volume_linear = float(voice.gain) * envelope.value_at(now)

func _clip(arrangement: String) -> NativeAudioClip:
	if clips.has(arrangement):
		return clips[arrangement]
	var path := "res://assets/audio/native/%s_fallback.res" % arrangement
	var clip := load(path) as NativeAudioClip if ResourceLoader.exists(path) else null
	if clip == null or not clip.valid() or clip.centered == null or clip.channel_count != 0 or clip.source.get("layer") != "procedural_music":
		push_error("Missing original procedural music resource; regenerate and import source audio: " + path)
		return null
	clips[arrangement] = clip
	return clip

func _now() -> float:
	return buses.context_seconds()

func _exit_tree() -> void:
	configured = false
	for voice: Dictionary in voices:
		voice.player.stop()
	voices.clear()
	current = {}
	clips.clear()
