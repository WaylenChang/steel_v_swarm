class_name AudioMusicFallback
extends Node

const PcmGain = preload("res://scripts/audio_pcm_gain.gd")

signal unavailable(mood: String, error: Error)

var metadata: Dictionary = {}
var preferences: AudioPreferences
var buses: AudioBuses
var clips: Dictionary = {}
var voices: Array[Dictionary] = []
var current: Dictionary = {}
var configured := false
var retired := false
var resources := preload("res://scripts/audio_resource_snapshot.gd").new()

func configure(rules: Dictionary, profile: AudioPreferences, routing: AudioBuses) -> Error:
	if retired or not is_inside_tree() or is_queued_for_deletion():
		return ERR_UNCONFIGURED
	if configured:
		return ERR_ALREADY_IN_USE
	if not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
		return ERR_UNCONFIGURED
	metadata = rules
	preferences = profile
	buses = routing
	buses.retiring.connect(_retire, CONNECT_ONE_SHOT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	configured = true
	return OK

func start(mood: String) -> void:
	if not _active():
		return
	if not current.is_empty() and current.mood == mood:
		return
	var now := _now()
	_stop(now)
	var arrangement := "battle" if mood == "battle" else "menu"
	var clip := _clip(arrangement)
	if not _active():
		return
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
	player.volume_linear = PcmGain.native_gain(player.stream, clip.centered_gain * envelope.value_at(start_time))
	var voice := {"mood": mood, "player": player, "envelope": envelope, "gain": clip.centered_gain, "retire_wall": INF}
	current = voice
	voices.append(voice)
	add_child(player)
	if not _active() or current != voice:
		return
	player.play()

func stop() -> void:
	if _active():
		_stop(_now())

func _stop(now: float) -> void:
	if current.is_empty():
		return
	current.envelope.release(now)
	current.retire_wall = Time.get_ticks_usec() / 1000000.0 + float(metadata.proceduralMusic.retirementSeconds)
	current = {}

func set_volume(gain: float) -> void:
	if not _active() or current.is_empty():
		return
	if not is_finite(gain):
		unavailable.emit(current.mood, ERR_INVALID_PARAMETER)
		return
	current.envelope.set_volume(_now(), gain)

func _process(_delta: float) -> void:
	if not _active():
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
		voice.player.volume_linear = PcmGain.native_gain(voice.player.stream, float(voice.gain) * envelope.value_at(now))

func _clip(arrangement: String) -> NativeAudioClip:
	if clips.has(arrangement):
		return clips[arrangement]
	var clip := resources.music(arrangement)
	if clip == null or not clip.valid() or clip.centered == null or clip.channel_count != 0 or clip.source.get("layer") != "procedural_music":
		push_error("Missing original procedural music resource; regenerate and import complete source audio: " + arrangement)
		return null
	clips[arrangement] = clip
	return clip

func _now() -> float:
	return buses.context_seconds()

func _active() -> bool:
	return configured and not retired and is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(buses) and buses.available()

func _retire() -> void:
	if retired:
		return
	retired = true
	configured = false
	if is_instance_valid(buses) and buses.retiring.is_connected(_retire):
		buses.retiring.disconnect(_retire)
	for voice: Dictionary in voices:
		voice.envelope.disconnect_output()
		voice.player.stop()
		voice.player.stream = null
	voices.clear()
	current = {}
	clips.clear()

func _exit_tree() -> void:
	_retire()
