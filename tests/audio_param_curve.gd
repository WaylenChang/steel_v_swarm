extends Node

const ParamCurve = preload("res://scripts/audio_param_curve.gd")
const Oscillator = preload("res://scripts/audio_move_oscillator.gd")
var assertions := 0
var failures := 0

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	var captured: Dictionary = Content.read_json("res://data/audio_move_oscillators/48000.json")
	for witness: Dictionary in captured.oscillators:
		var curve := ParamCurve.new()
		_check(curve.configure(witness.frequency, captured.sampleRate) == OK, "Configure original frequency curve")
		for command: Dictionary in witness.commands:
			_check(curve.queue(command.parameterTarget, command.time, command.tau) == OK, "Queue original AudioParam multiplication target")
		var values := curve.render(witness.frames)
		var expected := Marshalls.base64_to_raw(witness.frequencyValues)
		_check(values.to_byte_array() == expected, "Every generated Float32 frequency equals the original " + str(witness.category))
		var oscillator := Oscillator.new()
		oscillator.configure(captured.waveTables, witness.type)
		_check(oscillator.render(values).to_byte_array() == Marshalls.base64_to_raw(witness.values), "Original commands reconstruct every isolated oscillator sample without observed frequency input")
		var split := ParamCurve.new()
		split.configure(witness.frequency, captured.sampleRate)
		for command: Dictionary in witness.commands:
			split.queue(command.parameterTarget, command.time, command.tau)
		var output := PackedFloat32Array()
		for index in range(witness.frames / 128):
			output.append_array(split.render(128))
		_check(output.to_byte_array() == values.to_byte_array() and split.value == curve.value and split.frame == curve.frame, "Caller batch sizes preserve source quantum rounding")
		var before: float = curve.value
		_check(curve.render(127).is_empty() and curve.value == before and curve.frame == witness.frames, "Incomplete source quanta do not advance state")
		_check(curve.queue(1, 0, .14) == ERR_BUSY and curve.value == before, "Late commands reject without changing source state")
	for invalid: float in [NAN, INF, -1, 7999, 48000.5]:
		_check(ParamCurve.new().configure(1, invalid) != OK, "Reject unavailable context rates")
	var rejected := ParamCurve.new()
	_check(rejected.queue(1, 0, .14) == ERR_UNCONFIGURED and rejected.render(128).is_empty(), "Unconfigured curves cannot run")
	rejected.configure(1, 48000)
	for command: PackedFloat64Array in [PackedFloat64Array([NAN, 0, .14]), PackedFloat64Array([1, NAN, .14]), PackedFloat64Array([1, -1, .14]), PackedFloat64Array([1, 0, -1])]:
		_check(rejected.queue(command[0], command[1], command[2]) == ERR_INVALID_DATA and rejected.events.is_empty(), "Invalid commands leave the pending timeline unchanged")
	_check(rejected.queue(1, 0, 1e-50) == ERR_UNAVAILABLE, "Unavailable Float32 time constants reject")
	rejected.queue(0, .5, .14)
	_check(rejected.queue(1, .5, 0) == ERR_UNAVAILABLE and rejected.events.size() == 1, "Unimplemented coincident step/target event types reject explicitly")
	for count: int in [-128, 0, 127]:
		_check(rejected.render(count).is_empty() and rejected.frame == 0, "Invalid output extents leave the source timeline unchanged")
	for probe: Dictionary in captured.parameterProbes:
		var curve := ParamCurve.new()
		curve.configure(probe.initial, captured.sampleRate)
		var commands := Marshalls.base64_to_raw(probe.commandValues.data).to_float64_array()
		for index in range(0, commands.size(), 3):
			_check(curve.queue(commands[index], commands[index + 1], commands[index + 2]) == OK, "Queue exact original or boundary parameter words")
		var actual := curve.render(probe.frames)
		var expected := Marshalls.base64_to_raw(probe.values).to_float32_array()
		var maximum := 0.0
		var first := -1
		for index in range(actual.size()):
			if actual[index] != expected[index]:
				if first < 0:
					first = index
				maximum = maxf(maximum, absf(actual[index] - expected[index]))
		print("PARAM_CURVE_WITNESS ", probe.name, " maximum=", maximum, " first=", first)
		_check(actual.to_byte_array() == expected.to_byte_array(), "Original Float32 parameter curve: " + str(probe.name))
		if probe.name == "fractional-tails":
			var live := ParamCurve.new()
			live.configure(probe.initial, captured.sampleRate)
			for index in range(0, 6, 3):
				live.queue(commands[index], commands[index + 1], commands[index + 2])
			var output: PackedFloat32Array = live.render(128)
			for index in range(6, commands.size(), 3):
				_check(live.queue(commands[index], commands[index + 1], commands[index + 2]) == OK, "A fractional event may still reach the next editable sample")
			output.append_array(live.render(int(probe.frames) - 128))
			_check(output.to_byte_array() == expected.to_byte_array(), "Live fractional delivery retains the original curve without rounding its start time")
	print("AUDIO_PARAM_CURVE_PASS " if failures == 0 else "AUDIO_PARAM_CURVE_FAIL ", assertions, " assertions, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
