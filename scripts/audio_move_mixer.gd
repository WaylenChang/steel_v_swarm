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
var startup_budget_frames := 0
var startup_history_frames := 0
var lfo_waveform := PackedFloat32Array()
var lfo_frequency := 0.0
var lfo_scaled := false
var lfo_phase := 0.0
var diagnostics: Dictionary = {}
var has_oscillator_input := false
var last_pump_usec := 0
var max_service_gap_usec := 0
var pump_started_usec := 0

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
		lfo_frequency = float(plan.lfos[node].frequency) / bank.cycles(category, node)
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
		# Only rate changes affect samples already generated into the input ring.
		# Gain, pan and wetness remain editable until the output consumes them.
		var input_command: bool = has_oscillator_input and command.key == "rate"
		var editable := maxi(controls.frame, input_controls.frame) if input_command else controls.frame
		late_control_frames = maxi(late_control_frames, editable - wanted)
		var at_frame := maxi(wanted, editable)
		controls.queue(command.key, command.target, command.tau, at_frame)
		if input_command:
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
		var base_frequency := float(branch.frequency) / bank.cycles(category, int(branch.source))
		var frames := PackedVector2Array()
		frames.resize(count)
		for index in range(count):
			input_controls.begin_frame()
			var value := _lookup(waveform, oscillator_phase)
			frames[index] = Vector2(value, value)
			var frequency := base_frequency * (input_controls.values[2] if branch.rate_scaled else 1.0)
			oscillator_phase = fposmod(oscillator_phase + frequency / sample_rate, 1.0)
			input_controls.end_frame()
		if count > 0 and not playback.push_buffer(frames):
			return _fault("oscillator_buffer", ERR_CANT_CREATE)
	return true

func prepare() -> bool:
	return _commands() and prime_inputs()

func prime_output(frames: int) -> bool:
	var history := 0
	for input: Dictionary in inputs:
		history = maxi(history, int(input.get("startup_discard", 0)))
	# Removing input history must not also spend the two-period service reserve.
	# Restore whole native refills so an off-block cursor retains that reserve.
	startup_budget_frames = frames
	startup_history_frames = ceili(float(history) / AudioGeneratorFeed.REFILL_FRAMES) * AudioGeneratorFeed.REFILL_FRAMES
	startup_frames = frames + startup_history_frames
	input_ahead = maxi(input_ahead, frames)
	var silence := PackedVector2Array()
	silence.resize(startup_frames)
	silence.fill(Vector2.ZERO)
	return output.push_buffer(silence)

func pump() -> bool:
	pump_started_usec = Time.get_ticks_usec()
	if last_pump_usec > 0:
		max_service_gap_usec = maxi(max_service_gap_usec, pump_started_usec - last_pump_usec)
	last_pump_usec = pump_started_usec
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
		# Native playback history is not source time. Align each branch before
		# advancing the common gain/pan/LFO clock or combining dry and wet beds.
		var discard := mini(int(input.get("startup_discard", 0)), capture.get_frames_available())
		if discard > 0:
			capture.get_buffer(discard)
			input.startup_discard = int(input.startup_discard) - discard
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
	var pan_value := NAN
	var pan_coefficients := Vector2.ZERO
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
		if controls.values[1] != pan_value:
			pan_value = controls.values[1]
			pan_coefficients = AudioPan.mono_coefficients(pan_value)
		frames[index] = pan_coefficients * value * controls.values[0]
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
	var source_frames: Array[int] = []
	for input: Dictionary in inputs:
		source_frames.append(input.capture.get_frames_available())
	mutex.lock()
	diagnostics = {"frames": controls.frame, "input_frames": input_controls.frame,
		"startup_frames": startup_frames, "late_control_frames": late_control_frames,
		"startup_budget_frames": startup_budget_frames, "startup_history_frames": startup_history_frames,
		"lfo_phase": lfo_phase, "ready": announced, "output_skips": output.get_skips(),
		"gain": controls.values[0], "rate": controls.values[2], "wet": controls.values[3],
		"output_position": output.get_playback_position(), "output_available": output.get_frames_available(),
		"source_frames": source_frames, "max_service_gap_usec": max_service_gap_usec,
		"pump_usec": Time.get_ticks_usec() - pump_started_usec}
	mutex.unlock()

static func _lookup(waveform: PackedFloat32Array, phase: float) -> float:
	var position := phase * waveform.size()
	var index := floori(position)
	return lerpf(waveform[index], waveform[(index + 1) % waveform.size()], position - index)

func _fault(operation: String, error: Error) -> bool:
	var source_frames: Array[int] = []
	for input: Dictionary in inputs:
		source_frames.append(input.capture.get_frames_available())
	mutex.lock()
	stopping = true
	commands.clear()
	diagnostics.failure = operation
	diagnostics.error = error
	diagnostics.frames = controls.frame
	diagnostics.source_frames = source_frames
	diagnostics.max_service_gap_usec = max_service_gap_usec
	diagnostics.pump_usec = Time.get_ticks_usec() - pump_started_usec
	if output != null:
		diagnostics.output_skips = output.get_skips()
		diagnostics.output_position = output.get_playback_position()
		diagnostics.output_available = output.get_frames_available()
	mutex.unlock()
	failed.emit(operation, error)
	return false
