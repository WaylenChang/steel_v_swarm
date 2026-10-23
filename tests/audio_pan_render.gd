extends Node

var buses: AudioBuses
var capture: AudioEffectCapture
var sink: StringName
var results: Array = []
var retiring: Array[StringName] = []

func _ready() -> void:
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	if not fixtures.has("audioPan") or not fixtures.has("audioFilters"):
		_fail("Regenerate original audio panner impulses")
		return
	# Capture before a private muted sink; test pulses must not reach the device.
	sink = StringName("AudioPanSink_%d" % get_instance_id())
	AudioServer.add_bus()
	var sink_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sink_index, str(sink))
	AudioServer.set_bus_mute(sink_index, true)
	buses = AudioBuses.new()
	add_child(buses)
	if buses.configure() != OK:
		_fail("AUDIO_PAN_BUS_SETUP")
		return
	var index := AudioServer.get_bus_index(buses.sfx)
	AudioServer.set_bus_send(index, sink)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(index, capture)
	for fixture: Dictionary in fixtures.audioPan:
		if not await _case(fixture):
			return
	for fixture: Dictionary in fixtures.audioFilters:
		if not await _filter_case(fixture):
			return
	var file := FileAccess.open("res://tests/audio-pan-native.json", FileAccess.WRITE)
	if file == null:
		_fail("AUDIO_PAN_CAPTURE_OUTPUT")
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	if not await _cleanup():
		push_error("AUDIO_PAN_ROUTE_RETIREMENT_TIMEOUT")
		get_tree().quit(1)
		return
	print("AUDIO_PAN_NATIVE_PASS cases=", results.size(), " nativeMixCaptured=true audibleAcceptanceRequired=true")
	get_tree().quit()

func _case(fixture: Dictionary) -> bool:
	capture.clear_buffer()
	var clip := NativeAudioClip.new()
	clip.channel_count = fixture.input.size()
	for index in range(fixture.input.size()):
		var normalization := 2.0 if index == 0 else 4.0
		clip.panned_gains.append(normalization)
		clip.panned.append(_wave(float(fixture.input[index]) / normalization))
	var voice := AudioVoice.new()
	buses.add_child(voice)
	if voice.start(clip, buses, 1.0, float(fixture.pan)) != OK:
		voice.free()
		_fail("AUDIO_PAN_VOICE_SETUP")
		return false
	var deadline := Time.get_ticks_msec() + 2000
	while is_instance_valid(voice) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.025).timeout
	if is_instance_valid(voice):
		voice.free()
		_fail("AUDIO_PAN_VOICE_TIMEOUT")
		return false
	await get_tree().create_timer(.05).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	if frames.is_empty():
		_fail("AUDIO_PAN_CAPTURE_EMPTY")
		return false
	var left := 0.0
	var right := 0.0
	for frame: Vector2 in frames:
		left = maxf(left, frame.x)
		right = maxf(right, frame.y)
	# Source capture is float; native mono assets use Godot's 16-bit PCM format.
	var peak := 32767.0 / 32768.0
	var expected_left := float(fixture.left) * peak
	var expected_right := float(fixture.right) * peak
	var tolerance := 4.0 / 32768.0
	results.append({"pan": fixture.pan, "input": fixture.input, "left": left, "right": right,
		"expected_left": expected_left, "expected_right": expected_right, "frames": frames.size()})
	if absf(left - expected_left) > tolerance or absf(right - expected_right) > tolerance:
		_fail("AUDIO_PAN_NATIVE_MIX_MISMATCH %s" % JSON.stringify(results[-1]))
		return false
	return true

func _filter_case(fixture: Dictionary) -> bool:
	var rate := floori(AudioServer.get_mix_rate())
	if not fixture.responses.has(str(rate)):
		_fail("Regenerate source low-pass impulses for native mix rate: " + str(rate))
		return false
	capture.clear_buffer()
	var stream := _wave(0)
	var bytes: PackedByteArray = stream.data
	bytes.encode_s16(4096 * 2, 32767)
	stream.data = bytes
	var voice := AudioVoice.new()
	buses.add_child(voice)
	if voice.start_synthesis([{"stream": stream, "gain": 1.0, "route": "centered", "effects": [fixture.effect]}], buses, 0) != OK:
		voice.free()
		_fail("AUDIO_NATIVE_FILTER_SETUP")
		return false
	var deadline := Time.get_ticks_msec() + 2000
	while is_instance_valid(voice) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.025).timeout
	if is_instance_valid(voice):
		voice.free()
		_fail("AUDIO_NATIVE_FILTER_TIMEOUT")
		return false
	await get_tree().create_timer(.05).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var start := 0
	while start < frames.size() and frames[start].length_squared() < .00000000000001:
		start += 1
	var expected: Array = fixture.responses[str(rate)]
	if start + expected.size() > frames.size():
		_fail("AUDIO_NATIVE_FILTER_CAPTURE_INCOMPLETE")
		return false
	var maximum_error := 0.0
	for index in range(expected.size()):
		var value := float(expected[index]) * 32767.0 / 32768.0
		maximum_error = maxf(maximum_error, absf(frames[start + index].x - value))
		maximum_error = maxf(maximum_error, absf(frames[start + index].y - value))
	results.append({"filter": fixture.effect.type, "mixRate": rate, "maximumError": maximum_error, "samples": expected.size()})
	if maximum_error > .00005:
		_fail("AUDIO_NATIVE_FILTER_MISMATCH " + JSON.stringify(results[-1]))
		return false
	return true

func _wave(value: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(16384 * 2)
	bytes.fill(0)
	for frame in range(4096, 8192):
		bytes.encode_s16(frame * 2, floori(value * 32767.0 + .5))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = floori(AudioServer.get_mix_rate())
	stream.data = bytes
	return stream

func _cleanup() -> bool:
	if is_instance_valid(buses):
		retiring = buses.owned.duplicate()
		buses.free()
	var deadline := Time.get_ticks_msec() + 2000
	while retiring.any(func(name): return AudioServer.get_bus_index(name) >= 0) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.02, true, false, true).timeout
	var index := AudioServer.get_bus_index(sink)
	if index > 0:
		AudioServer.remove_bus(index)
	return retiring.all(func(name): return AudioServer.get_bus_index(name) < 0)

func _fail(message: String) -> void:
	await _cleanup()
	push_error(message)
	get_tree().quit(1)
