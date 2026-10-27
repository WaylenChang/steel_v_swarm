extends Node

const Oscillator = preload("res://scripts/audio_move_oscillator.gd")
var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	var captured: Dictionary = Content.read_json("res://data/audio_move_oscillators/48000.json")
	var tables: Dictionary = captured.waveTables
	var witnesses: Array = captured.oscillators.duplicate()
	witnesses.append_array(tables.probes)
	for witness: Dictionary in witnesses:
		var name: String = witness.get("category", "boundary:" + str(witness.type))
		var oscillator := Oscillator.new()
		_check(oscillator.configure(tables, witness.type) == OK, "Load original band-limited " + str(witness.type))
		var frequencies := Marshalls.base64_to_raw(witness.frequencyValues).to_float32_array()
		var expected := Marshalls.base64_to_raw(witness.values).to_float32_array()
		var started := Time.get_ticks_usec()
		var actual := oscillator.render(frequencies)
		var elapsed := Time.get_ticks_usec() - started
		var maximum := 0.0
		if actual.size() == expected.size():
			for index in range(actual.size()):
				maximum = maxf(maximum, absf(actual[index] - expected[index]))
		print("MOVE_OSCILLATOR_WITNESS ", name, " maximum=", maximum, " render_usec=", elapsed)
		_check(actual.to_byte_array() == expected.to_byte_array(), "Every native sample matches the original isolated " + name)
		var split := Oscillator.new()
		split.configure(tables, witness.type)
		var output := PackedFloat32Array()
		for start in range(0, frequencies.size(), 508):
			output.append_array(split.render(frequencies.slice(start, mini(start + 508, frequencies.size()))))
		_check(output.to_byte_array() == actual.to_byte_array() and split.phase == oscillator.phase and split.frame == oscillator.frame, "Source grouping and phase survive non-quantum caller boundaries")
		var before: float = oscillator.phase
		for invalid: PackedFloat32Array in [PackedFloat32Array([1]), PackedFloat32Array([1, 1, NAN, 1]), PackedFloat32Array([1, 0, 1, 1]), PackedFloat32Array([24000, 1, 1, 1])]:
			_check(oscillator.render(invalid).is_empty() and oscillator.phase == before and oscillator.frame == frequencies.size(), "Invalid and incomplete input cannot partly advance the source oscillator")
	for change in range(7):
		var invalid := tables.duplicate(true)
		match change:
			0: invalid.sampleRate = 7999
			1: invalid.frames = 4095
			2: invalid.types[0].tables.pop_back()
			3: invalid.types[0].tables[0].values += "!"
			4: invalid.types.append(invalid.types[0])
			5:
				var bytes := Marshalls.base64_to_raw(invalid.types[0].tables[0].values)
				bytes.encode_float(0, NAN)
				invalid.types[0].tables[0].values = Marshalls.raw_to_base64(bytes)
			6: invalid.types[0].tables[0].values[0] = "!"
		_check(Oscillator.new().configure(invalid, str(tables.types[0].type)) != OK, "Reject unavailable, malformed or ambiguous wave tables")
	_check(Oscillator.new().configure(tables, "triangle") == ERR_UNAVAILABLE, "Uncaptured oscillator shapes remain unavailable")
	print("AUDIO_MOVE_OSCILLATOR_PASS " if failures == 0 else "AUDIO_MOVE_OSCILLATOR_FAIL ", assertions, " assertions, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
