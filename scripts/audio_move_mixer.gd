class_name AudioMoveMixer
extends RefCounted

signal ready
signal failed(operation: String, error: Error)

var mutex := Mutex.new()
var commands: Array[Dictionary] = []
var stopping := false
var category := ""
var plan: Dictionary = {}
var bank: NativeAudioMoveBank
var inputs: Array[Dictionary] = []
var output: AudioStreamGeneratorPlayback
var controls := AudioMoveControls.new()
var input_controls := AudioMoveControls.new()
var sample_rate := 0.0
var origin := 0.0
var announced := false
var oscillator_phase := 0.0
var input_ahead := 0
var late_control_frames := 0
var startup_frames := 0
var lfo_waveform := PackedFloat32Array()
var lfo_frequency := 0.0
var lfo_scaled := false
var lfo_phase := 0.0
var diagnostics: Dictionary = {}
var has_oscillator_input := false

func configure(name: String, graph_plan: Dictionary, wave_bank: NativeAudioMoveBank, initial: Dictionary, rate: float, start_time: float) -> void:
	category = name
	plan = graph_plan
	bank = wave_bank
	sample_rate = rate
	origin = start_time
	input_ahead = ceili(rate * .02)
	controls.configure(initial, rate)
	input_controls.configure(initial, rate)
	for branch: Dictionary in plan.branches:
		has_oscillator_input = has_oscillator_input or branch.kind == "oscillator"
	for node: int in plan.lfos:
		lfo_waveform = bank.waveform(category, node)
		lfo_frequency = float(plan.lfos[node].frequency)
		lfo_scaled = bool(plan.lfos[node].rate_scaled)

func queue(key: String, target: float, tau: float, time: float) -> void:
	mutex.lock()
	if not stopping:
		commands.append({"key": key, "target": target, "tau": tau, "time": time})
	mutex.unlock()

func stop() -> void:
	mutex.lock()
	stopping = true
	mutex.unlock()

func _commands() -> bool:
	mutex.lock()
	var done := stopping
	var pending := commands
	commands = []
	mutex.unlock()
	if done:
		return false
	for command: Dictionary in pending:
		var wanted := maxi(0, ceili((float(command.time) - origin) * sample_rate))
		var editable := maxi(controls.frame, input_controls.frame)
		late_control_frames = maxi(late_control_frames, editable - wanted)
		var at_frame := maxi(wanted, editable)
		controls.queue(command.key, command.target, command.tau, at_frame)
		if has_oscillator_input:
			input_controls.queue(command.key, command.target, command.tau, at_frame)
	return true

func prime_inputs() -> bool:
	for input: Dictionary in inputs:
		if not input.has("playback"):
			continue
		var playback: AudioStreamGeneratorPlayback = input.playback
		var available := playback.get_frames_available()
		var queued := int(input.capacity) - available
		var count := mini(available, maxi(0, input_ahead - queued))
		var branch: Dictionary = input.branch
		var waveform := bank.waveform(category, int(branch.source))
		var frames := PackedVector2Array()
		frames.resize(count)
		for index in range(count):
			input_controls.begin_frame()
			var value := _lookup(waveform, oscillator_phase)
			frames[index] = Vector2(value, value)
			var frequency := float(branch.frequency) * (input_controls.values[2] if branch.rate_scaled else 1.0)
			oscillator_phase = fposmod(oscillator_phase + frequency / sample_rate, 1.0)
			input_controls.end_frame()
		if count > 0 and not playback.push_buffer(frames):
			return _fault("oscillator_buffer", ERR_CANT_CREATE)
	return true

func prepare() -> bool:
	return _commands() and prime_inputs()

func prime_output(frames: int) -> bool:
	startup_frames = frames
	input_ahead = maxi(input_ahead, frames)
	var silence := PackedVector2Array()
	silence.resize(frames)
	silence.fill(Vector2.ZERO)
	return output.push_buffer(silence)

func pump() -> bool:
	if not _commands() or not prime_inputs():
		return false
	if output.get_skips() > 0:
		return _fault("output_underrun", ERR_BUSY)
	for input: Dictionary in inputs:
		if input.has("playback") and input.playback.get_skips() > 0:
			return _fault("oscillator_underrun", ERR_BUSY)
	var count := output.get_frames_available()
	var captured: Array[PackedVector2Array] = []
	var discarded := false
	# Both stomp captures must be consumed at the same driver boundary.
	AudioServer.lock()
	for input: Dictionary in inputs:
		var capture: AudioEffectCapture = input.capture
		count = mini(count, capture.get_frames_available())
		discarded = discarded or capture.get_discarded_frames() > int(input.discard_origin)
	if count > 0 and not discarded:
		for input: Dictionary in inputs:
			captured.append(input.capture.get_buffer(count))
	AudioServer.unlock()
	if discarded:
		return _fault("capture_overflow", ERR_OUT_OF_MEMORY)
	if count <= 0:
		_publish()
		return true
	var frames := PackedVector2Array()
	frames.resize(count)
	for index in range(count):
		controls.begin_frame()
		var modulation := 0.0
		if not lfo_waveform.is_empty():
			modulation = _lookup(lfo_waveform, lfo_phase)
			var frequency := lfo_frequency * (controls.values[2] if lfo_scaled else 1.0)
			lfo_phase = fposmod(lfo_phase + frequency / sample_rate, 1.0)
		var value := 0.0
		for branch_index in range(inputs.size()):
			var branch: Dictionary = inputs[branch_index].branch
			var sample := float(captured[branch_index][index].x) * float(branch.gain)
			if not branch.modulation.is_empty():
				sample *= float(branch.modulation.offset) + float(branch.modulation.depth) * modulation
			if branch.weight == "dry":
				sample *= 1.0 - controls.values[3]
			elif branch.weight == "wet":
				sample *= controls.values[3]
			value += sample
		var pan := AudioPan.mono_coefficients(controls.values[1])
		frames[index] = pan * value * controls.values[0]
		controls.end_frame()
	AudioServer.lock()
	for input: Dictionary in inputs:
		for filter: Dictionary in input.filters:
			if filter.rate_scaled:
				filter.effect.cutoff_hz = float(filter.frequency) * controls.values[2]
	AudioServer.unlock()
	if not output.push_buffer(frames):
		return _fault("output_buffer", ERR_CANT_CREATE)
	if not announced:
		announced = true
		ready.emit()
	_publish()
	return true

func snapshot() -> Dictionary:
	mutex.lock()
	var result := diagnostics.duplicate(true)
	mutex.unlock()
	return result

func _publish() -> void:
	mutex.lock()
	diagnostics = {"frames": controls.frame, "input_frames": input_controls.frame,
		"startup_frames": startup_frames, "late_control_frames": late_control_frames,
		"lfo_phase": lfo_phase, "ready": announced, "output_skips": output.get_skips(),
		"gain": controls.values[0], "rate": controls.values[2], "wet": controls.values[3]}
	mutex.unlock()

static func _lookup(waveform: PackedFloat32Array, phase: float) -> float:
	var position := phase * waveform.size()
	var index := floori(position)
	return lerpf(waveform[index], waveform[(index + 1) % waveform.size()], position - index)

func _fault(operation: String, error: Error) -> bool:
	mutex.lock()
	stopping = true
	commands.clear()
	diagnostics.failure = operation
	diagnostics.error = error
	mutex.unlock()
	failed.emit(operation, error)
	return false
