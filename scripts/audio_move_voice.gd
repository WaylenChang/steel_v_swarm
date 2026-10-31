class_name AudioMoveVoice
extends Node

const PcmGain = preload("res://scripts/audio_pcm_gain.gd")
const SampleFilter = preload("res://scripts/audio_move_filter.gd")
const SourceDsp = preload("res://scripts/audio_move_source_dsp.gd")
const WaveBank = preload("res://scripts/native_audio_move_waves.gd")
const Identity = preload("res://scripts/audio_resource_identity.gd")

signal failed(operation: String, error: Error)

var mixer := AudioMoveMixer.new()
var buses: AudioBuses
var input_players: Array[AudioStreamPlayer] = []
var output_player: AudioStreamPlayer
var routes: Array[StringName] = []
var configured := false
var disposed := false
var activated := false
var context_origin := 0.0

func configure(category: String, metadata: Dictionary, bank: NativeAudioMoveBank, routing: AudioBuses, initial: Dictionary, origin: float, wave_bank: WaveBank = null) -> Error:
	if configured or disposed or not is_inside_tree() or is_queued_for_deletion():
		return ERR_UNCONFIGURED
	if not is_instance_valid(routing) or routing.is_queued_for_deletion() or not routing.available():
		return ERR_UNCONFIGURED
	var plan := AudioMovePlan.compile(metadata.moveGraphs[category])
	if plan.is_empty() or plan.lfos.size() > 1:
		return ERR_UNAVAILABLE
	var oscillator_count := 0
	for node: int in plan.lfos:
		if bank.waveform(category, node).is_empty():
			return ERR_INVALID_DATA
	for branch: Dictionary in plan.branches:
		if branch.kind == "oscillator":
			oscillator_count += 1
			if bank.waveform(category, int(branch.source)).is_empty():
				return ERR_INVALID_DATA
	if oscillator_count > 1:
		return ERR_UNAVAILABLE
	if wave_bank != null:
		if wave_bank.movement_hash != Identity.digest(bank):
			return ERR_INVALID_DATA
		var dsp := SourceDsp.new()
		var error := dsp.configure(metadata.moveGraphs[category], plan, initial, AudioServer.get_mix_rate(), wave_bank)
		if error != OK:
			return error
		mixer.source_dsp = dsp
	process_mode = Node.PROCESS_MODE_ALWAYS
	buses = routing
	buses.retiring.connect(retire, CONNECT_ONE_SHOT)
	context_origin = origin
	var rate := AudioServer.get_mix_rate()
	mixer.configure(category, plan, bank, initial, rate, 0)
	mixer.failed.connect(_stream_failed, Object.CONNECT_DEFERRED)
	for branch: Dictionary in plan.branches:
		var effects: Array[AudioEffect] = []
		var filters: Array[Dictionary] = []
		var correction := 1.0
		var raw_capture: AudioEffectCapture
		var raw_input_gain := 1.0
		if branch.filters.size() > 1 and branch.filters.any(func(entry: Dictionary): return entry.rate_scaled):
			return ERR_UNAVAILABLE
		for captured: Dictionary in branch.filters:
			if captured.rate_scaled:
				var processor := SampleFilter.new()
				if processor.configure(captured.captured, rate) != OK:
					return ERR_UNAVAILABLE
				raw_capture = AudioEffectCapture.new()
				raw_capture.buffer_length = .5
				effects.append(raw_capture)
				var native := AudioSourceFilter.create(captured.captured)
				effects.append(native)
				correction *= AudioSourceFilter.gain_correction(captured.captured)
				raw_input_gain = 1.0 / correction
				filters.append({"processor": processor, "node": captured.node, "rate_scaled": true})
				continue
			var effect := AudioSourceFilter.create(captured.captured) as AudioEffectFilter
			if effect == null:
				return ERR_UNAVAILABLE
			effects.append(effect)
			correction *= AudioSourceFilter.gain_correction(captured.captured)
			filters.append({"effect": effect, "frequency": effect.cutoff_hz, "rate_scaled": captured.rate_scaled})
		var capture := AudioEffectCapture.new()
		capture.buffer_length = .5
		effects.append(capture)
		var route := buses.capture_bus(effects)
		if route == &"":
			return ERR_UNCONFIGURED
		routes.append(route)
		var player := AudioStreamPlayer.new()
		player.bus = route
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.stream = bank.noise if branch.kind == "noise" else _generator(rate)
		player.volume_linear = PcmGain.native_gain(player.stream, correction * (bank.noise_gain if branch.kind == "noise" else 1.0))
		input_players.append(player)
		add_child(player)
		if not _admitting():
			return ERR_UNCONFIGURED
		var input := {"branch": branch, "capture": capture, "filters": filters,
			"startup_discard": AudioGeneratorFeed.input_latency_frames(branch.kind == "oscillator")}
		if raw_capture != null:
			input.raw_capture = raw_capture
			input.raw_input_gain = raw_input_gain
		if branch.kind == "oscillator":
			var feed := player.stream as AudioGeneratorFeed
			input.playback = feed.playback
			input.capacity = feed.playback.get_frames_available()
		mixer.inputs.append(input)
	output_player = AudioStreamPlayer.new()
	output_player.stream = _generator(rate)
	output_player.bus = buses.sfx
	output_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(output_player)
	if not _admitting():
		return ERR_UNCONFIGURED
	mixer.output = (output_player.stream as AudioGeneratorFeed).playback
	configured = true
	return OK

func _admitting() -> bool:
	return not disposed and is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(buses) and buses.available()

func activate() -> Error:
	if not configured or disposed or activated or not is_inside_tree() or is_queued_for_deletion():
		return ERR_UNCONFIGURED
	mixer.origin = buses.context_seconds() - context_origin
	var interval := AudioServer.get_time_to_next_mix() + AudioServer.get_time_since_last_mix()
	var frames := AudioGeneratorFeed.startup_frames(interval, AudioServer.get_mix_rate())
	if not mixer.prime_output(mini(frames, mixer.output.get_frames_available())):
		return ERR_CANT_CREATE
	if not mixer.prepare():
		return ERR_CANT_CREATE
	# Initial targets have now been applied to both oscillator and output cursors.
	mixer.origin = buses.context_seconds() - context_origin
	AudioServer.lock()
	for input: Dictionary in mixer.inputs:
		input.capture.clear_buffer()
		input.discard_origin = input.capture.get_discarded_frames()
		if input.has("raw_capture"):
			input.raw_capture.clear_buffer()
			input.raw_discard_origin = input.raw_capture.get_discarded_frames()
	for player: AudioStreamPlayer in input_players:
		player.play()
	# All native buffers are already filled; no pause/fade cycle advances input phase.
	output_player.play()
	AudioServer.unlock()
	activated = true
	return OK

static func _generator(rate: float) -> AudioGeneratorFeed:
	var stream := AudioGeneratorFeed.new()
	stream.configure(rate)
	return stream

func _stream_failed(operation: String, error: Error) -> void:
	if not configured:
		return
	mixer.stop()
	output_player.stop()
	for player: AudioStreamPlayer in input_players:
		player.stop()
	failed.emit(operation, error)

func retire() -> void:
	if disposed:
		return
	configured = false
	disposed = true
	if is_instance_valid(buses) and buses.retiring.is_connected(retire):
		buses.retiring.disconnect(retire)
	mixer.stop()
	if is_instance_valid(output_player):
		output_player.stop()
	for player: AudioStreamPlayer in input_players:
		player.stop()
	if is_instance_valid(buses):
		for route: StringName in routes:
			buses.release_voice(route)
	routes.clear()

func _exit_tree() -> void:
	retire()
