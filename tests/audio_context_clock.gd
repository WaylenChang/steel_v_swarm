extends Node

var assertions := 0
var failures: Array[String] = []
var buses: AudioBuses
var reference := AudioEffectCapture.new()
var reference_bus: StringName
var source: AudioStreamPlayer

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _counts() -> Vector2i:
	AudioServer.lock()
	var actual := roundi(buses.context_seconds() * buses.clock_rate)
	var expected := reference.get_pushed_frames() + reference.get_discarded_frames()
	AudioServer.unlock()
	return Vector2i(actual, expected)

func _observe(seconds: float, label: String) -> void:
	var start := _counts()
	var finish := start
	var deadline := Time.get_ticks_msec() + roundi(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.05, true, false, true).timeout
		finish = _counts()
		_check(finish.x - start.x == finish.y - start.y,
			label + ": silent SFX clock advances by the same native frames as the active reference bus")
	_check(finish.x > start.x, label + ": the native clock advances without SFX players")

func _run() -> void:
	buses = AudioBuses.new()
	add_child(buses)
	_check(buses.configure() == OK, "Create a native context with no SFX or music voices")
	reference_bus = StringName("AudioClock_%d" % get_instance_id())
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, reference_bus)
	AudioServer.set_bus_mute(index, true)
	reference.buffer_length = .01
	AudioServer.add_bus_effect(index, reference)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = roundi(AudioServer.get_mix_rate())
	var pcm := PackedByteArray()
	pcm.resize(wave.mix_rate * 2)
	for frame in range(wave.mix_rate):
		pcm.encode_s16(frame * 2, 4096)
	wave.data = pcm
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_end = wave.mix_rate
	source = AudioStreamPlayer.new()
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	source.stream = wave
	source.bus = reference_bus
	source.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(source)
	source.play()
	await get_tree().create_timer(.1, true, false, true).timeout
	# Outlast native bus auto-disable while an independent, muted PCM bus stays live.
	await _observe(3.0, "Silent idle")
	get_tree().paused = true
	Engine.time_scale = 0
	await _observe(.3, "Paused zero-scale scene")
	Engine.time_scale = .25
	await _observe(.3, "Paused slow-scale scene")
	Engine.time_scale = 4
	await _observe(.3, "Paused fast-scale scene")
	Engine.time_scale = 1
	get_tree().paused = false
	_check(buses.clock_capture.get_discarded_frames() > 0,
		"The context clock includes native frames discarded by its bounded PCM capture")
	source.stop()
	source.free()
	var names: Array[StringName] = buses.owned.duplicate()
	buses.free()
	var deadline := Time.get_ticks_msec() + 3000
	while names.any(func(name): return AudioServer.get_bus_index(name) >= 0) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.02, true, false, true).timeout
	_check(names.all(func(name): return AudioServer.get_bus_index(name) < 0), "The silent context retires its native clock routes")
	AudioServer.remove_bus(AudioServer.get_bus_index(reference_bus))
	print("AUDIO_CONTEXT_CLOCK assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
