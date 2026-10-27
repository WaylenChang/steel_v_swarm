extends Node

const Filter = preload("res://scripts/audio_move_filter.gd")
var assertions := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	var data: Dictionary = Content.read_json("res://data/audio_move_rates/48000.json")
	var selected: Dictionary
	var responses := 0
	for fixture: Dictionary in data.filters:
		if fixture.effect.type != "bandpass":
			continue
		selected = fixture.effect
		for rate: String in fixture.responses:
			var filter := Filter.new()
			_check(filter.configure(fixture.effect, float(rate)) == OK, "Configure an original band-pass impulse")
			var maximum := 0.0
			for index in range(fixture.responses[rate].size()):
				var actual := filter.process_sample(1.0 if index == 0 else 0.0, 1.0)
				maximum = maxf(maximum, absf(actual - float(fixture.responses[rate][index])))
			_check(maximum <= .000000954, "Original Chromium band-pass impulse at " + rate + ": " + str(maximum))
			responses += 1
	_check(responses == 9, "Cover every original movement band-pass at all captured rates")
	for rate: float in [NAN, 0, 7999]:
		_check(Filter.new().configure(selected, rate) == ERR_UNAVAILABLE, "Reject unavailable native context rates")
	var unsupported := selected.duplicate(true)
	unsupported.type = "lowpass"
	_check(Filter.new().configure(unsupported, 48000) == ERR_UNAVAILABLE, "Unimplemented dynamic filter shapes remain unavailable")
	var filter := Filter.new()
	filter.configure(selected, 48000)
	_check(is_nan(filter.process_sample(1, NAN)) and is_nan(filter.process_sample(1, 0)), "Invalid runtime modulation fails explicitly")
	var programs: Dictionary = Content.read_json("res://data/audio_move_rate_waveforms/48000.json")
	var controls := AudioMoveControls.new()
	controls.configure(programs.waveforms[0], 48000)
	var input_controls := AudioMoveControls.new()
	input_controls.configure(programs.waveforms[0], 48000)
	var batch := AudioMoveControls.new()
	batch.configure(programs.waveforms[0], 48000)
	for command: Dictionary in programs.waveforms[0].commands:
		controls.queue(command.key, command.target, command.tau, ceili(float(command.time) * 48000))
		batch.queue(command.key, command.target, command.tau, ceili(float(command.time) * 48000))
		if command.key == "rate":
			input_controls.queue(command.key, command.target, command.tau, ceili(float(command.time) * 48000))
	for count: int in [1024, 12000, 12000, 12000, 12000]:
		var before := controls.frame
		var preview := controls.preview_rate(count)
		_check(controls.frame == before, "Preview cannot advance the source clock")
		var actual := PackedFloat64Array()
		var expected_parameters: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()]
		for index in range(count):
			controls.begin_frame()
			actual.append(controls.values[2])
			for channel in range(4):
				expected_parameters[channel].append(controls.values[channel])
			controls.end_frame()
		_check(preview.to_byte_array() == actual.to_byte_array(), "Batch rate curves preserve every original control word")
		_check(input_controls.consume_rate(count).to_byte_array() == actual.to_byte_array() and input_controls.frame == controls.frame, "Oscillator-only advancement preserves every rate word and source frame")
		var parameters := batch.consume_frames(count)
		for channel in range(4):
			_check(parameters[channel].to_byte_array() == expected_parameters[channel].to_byte_array(), "Batch output controls preserve every scalar source word")
		_check(batch.values.to_byte_array() == controls.values.to_byte_array() and batch.frame == controls.frame, "Batch output controls retain the original final state and clock")
	var source := Marshalls.base64_to_raw(data.noise.values).to_float32_array()
	var samples := PackedVector2Array()
	samples.resize(source.size())
	for index in range(source.size()):
		samples[index] = Vector2(source[index], source[index])
	var timeline := AudioMoveControls.new()
	timeline.configure(programs.waveforms[0], 48000)
	for command: Dictionary in programs.waveforms[0].commands:
		timeline.queue(command.key, command.target, command.tau, ceili(float(command.time) * 48000))
	var rates := timeline.preview_rate(samples.size())
	var whole := Filter.new()
	var chunked := Filter.new()
	whole.configure(selected, 48000)
	chunked.configure(selected, 48000)
	var expected := whole.process_buffer(samples, rates)
	var actual := PackedVector2Array()
	for begin in range(0, samples.size(), 511):
		actual.append_array(chunked.process_buffer(samples.slice(begin, mini(begin + 511, samples.size())), rates.slice(begin, mini(begin + 511, rates.size()))))
	_check(expected.to_byte_array() == actual.to_byte_array(), "Original noise and rate programs retain exact filter state across buffer boundaries")
	var fixed := Filter.new()
	var transition := Filter.new()
	fixed.configure(selected, 48000)
	transition.configure(selected, 48000)
	var unity := PackedFloat64Array()
	unity.resize(samples.size())
	unity.fill(1)
	var native := fixed.process_buffer(samples, unity)
	var switched := PackedVector2Array()
	for begin in range(0, samples.size(), 511):
		var end := mini(begin + 511, samples.size())
		switched.append_array(transition.process_native_buffer(samples.slice(begin, end), native.slice(begin, end), rates.slice(begin, end), 1))
	var maximum := 0.0
	for index in range(expected.size()):
		maximum = maxf(maximum, absf(expected[index].x - switched[index].x))
	_check(transition.dynamic and maximum <= .000000954, "Native fixed-filter history bridges into the exact source rate program")
	print("AUDIO_MOVE_FILTER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
