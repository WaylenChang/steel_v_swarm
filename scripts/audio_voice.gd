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
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
		return ERR_UNCONFIGURED
	if clip == null or not clip.valid() or not is_finite(gain) or gain < 0 or not is_finite(pan) or not is_finite(rate) or rate <= 0:
		return ERR_INVALID_PARAMETER
	buses = routing
	buses.retiring.connect(dispose, CONNECT_ONE_SHOT)
	var matrix: Array[Dictionary] = AudioPan.routes(pan, clip.channel_count) if clip.channel_count > 0 else []
	for index in range(clip.panned.size()):
		var bus := buses.voice_bus(float(matrix[index].pan))
		if bus == &"" or not _active():
			if bus != &"" and is_instance_valid(buses):
				buses.release_voice(bus)
			dispose()
			return ERR_UNCONFIGURED
		routes.append(bus)
		var normalization := clip.panned_gains[index] if not clip.panned_gains.is_empty() else 1.0
		if not _player(clip.panned[index], bus, gain * float(matrix[index].gain) * normalization, rate):
			return ERR_UNCONFIGURED
	if clip.centered != null:
		if not _player(clip.centered, buses.sfx, gain * clip.centered_gain, rate):
			return ERR_UNCONFIGURED
	return OK if _play() else ERR_UNCONFIGURED

func start_synthesis(stems: Array[Dictionary], routing: AudioBuses, pan: float) -> Error:
	if not players.is_empty() or disposed:
		return ERR_ALREADY_IN_USE
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
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
	buses.retiring.connect(dispose, CONNECT_ONE_SHOT)
	for stem: Dictionary in prepared:
		var bus := buses.sfx
		if not stem.effects.is_empty():
			bus = buses.effect_bus(stem.effects)
			if bus == &"" or not _active():
				if bus != &"" and is_instance_valid(buses):
					buses.release_voice(bus)
				dispose()
				return ERR_UNCONFIGURED
			routes.append(bus)
		if not _player(stem.stream, bus, stem.gain, 1):
			return ERR_UNCONFIGURED
	return OK if _play() else ERR_UNCONFIGURED

func _play() -> bool:
	if not _active():
		dispose()
		return false
	pending = players.size()
	# Native WAV starts do not lock the driver; submit all stems in one mix boundary.
	AudioServer.lock()
	for player: AudioStreamPlayer in players:
		player.play()
	AudioServer.unlock()
	return true

func _active() -> bool:
	if disposed or not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(buses) or buses.is_queued_for_deletion() or not buses.available():
		return false
	for player: AudioStreamPlayer in players:
		if not is_instance_valid(player) or player.is_queued_for_deletion() or not player.is_inside_tree() or player.get_parent() != self:
			return false
	return true

func _player(stream: AudioStream, bus: StringName, gain: float, rate: float) -> bool:
	if not _active():
		return false
	var player := AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.bus = bus
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.volume_linear = gain
	player.pitch_scale = rate
	player.finished.connect(_finished)
	player.tree_exiting.connect(dispose, CONNECT_ONE_SHOT)
	players.append(player)
	add_child(player)
	if not _active():
		dispose()
		return false
	return true

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
	if is_instance_valid(buses) and buses.retiring.is_connected(dispose):
		buses.retiring.disconnect(dispose)
	for player: AudioStreamPlayer in players:
		if is_instance_valid(player):
			player.stop()
	queue_free()

func _exit_tree() -> void:
	disposed = true
	if is_instance_valid(buses) and buses.retiring.is_connected(dispose):
		buses.retiring.disconnect(dispose)
	for player: AudioStreamPlayer in players:
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(buses):
		for name: StringName in routes:
			buses.release_voice(name)
	routes.clear()
