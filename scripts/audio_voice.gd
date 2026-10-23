class_name AudioVoice
extends Node

var buses: AudioBuses
var players: Array[AudioStreamPlayer] = []
var routes: Array[StringName] = []
var pending := 0
var disposed := false

func start(clip: NativeAudioClip, routing: AudioBuses, gain: float, pan: float, rate: float = 1) -> Error:
	if not players.is_empty() or disposed:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree() or routing == null or not routing.available():
		return ERR_UNCONFIGURED
	if clip == null or not clip.valid() or not is_finite(gain) or gain < 0 or not is_finite(pan) or not is_finite(rate) or rate <= 0:
		return ERR_INVALID_PARAMETER
	buses = routing
	var matrix: Array[Dictionary] = AudioPan.routes(pan, clip.channel_count) if clip.channel_count > 0 else []
	for index in range(clip.panned.size()):
		var bus := buses.voice_bus(float(matrix[index].pan))
		routes.append(bus)
		var normalization := clip.panned_gains[index] if not clip.panned_gains.is_empty() else 1.0
		_player(clip.panned[index], bus, gain * float(matrix[index].gain) * normalization, rate)
	if clip.centered != null:
		_player(clip.centered, buses.sfx, gain * clip.centered_gain, rate)
	_play()
	return OK

func start_synthesis(stems: Array[Dictionary], routing: AudioBuses, pan: float) -> Error:
	if not players.is_empty() or disposed:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree() or routing == null or not routing.available():
		return ERR_UNCONFIGURED
	if stems.is_empty() or not is_finite(pan):
		return ERR_INVALID_PARAMETER
	var prepared: Array[Dictionary] = []
	for stem: Dictionary in stems:
		var stream: AudioStreamWAV = stem.get("stream") as AudioStreamWAV
		if stream == null or stream.stereo or stream.get_length() <= 0 or stem.get("route") not in ["panned", "centered"] or not is_finite(float(stem.get("gain", NAN))) or float(stem.gain) < 0:
			return ERR_INVALID_DATA
		var effects: Array[AudioEffect] = []
		var correction := 1.0
		for captured: Dictionary in stem.effects:
			var effect := AudioSourceFilter.create(captured)
			if effect == null:
				return ERR_UNAVAILABLE
			effects.append(effect)
			correction *= AudioSourceFilter.gain_correction(captured)
		var normalization := float(stem.gain) * correction
		if stem.route == "panned":
			var matrix: Dictionary = AudioPan.routes(pan, 1)[0]
			var panner := AudioEffectPanner.new()
			panner.pan = matrix.pan
			effects.append(panner)
			normalization *= float(matrix.gain)
		prepared.append({"stream": stream, "gain": normalization, "effects": effects})
	buses = routing
	for stem: Dictionary in prepared:
		var bus := buses.sfx
		if not stem.effects.is_empty():
			bus = buses.effect_bus(stem.effects)
			routes.append(bus)
		_player(stem.stream, bus, stem.gain, 1)
	_play()
	return OK

func _play() -> void:
	pending = players.size()
	# Native WAV starts do not lock the driver; submit all stems in one mix boundary.
	AudioServer.lock()
	for player: AudioStreamPlayer in players:
		player.play()
	AudioServer.unlock()

func _player(stream: AudioStream, bus: StringName, gain: float, rate: float) -> void:
	var player := AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.bus = bus
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.volume_linear = gain
	player.pitch_scale = rate
	player.finished.connect(_finished)
	players.append(player)
	add_child(player)

func _finished() -> void:
	if disposed:
		return
	pending -= 1
	if pending == 0:
		dispose()

func dispose() -> void:
	if disposed:
		return
	disposed = true
	for player: AudioStreamPlayer in players:
		player.stop()
	queue_free()

func _exit_tree() -> void:
	for player: AudioStreamPlayer in players:
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(buses):
		for name: StringName in routes:
			buses.release_voice(name)
	routes.clear()
