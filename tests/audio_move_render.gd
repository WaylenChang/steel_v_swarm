extends Node

var buses: AudioBuses
var movement: AudioMove
var capture: AudioEffectCapture
var sink: StringName
var failures: Array[Dictionary] = []
var results: Dictionary = {}

func _ready() -> void:
	if not Content.balance.get("audio", {}).has("moveGraphs") or not ResourceLoader.exists(NativeAudioMoveBank.PATH):
		_abort("Regenerate and import original movement audio")
		return
	sink = StringName("MoveAudioTest_%d" % get_instance_id())
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, str(sink))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(sink), true)
	buses = AudioBuses.new()
	add_child(buses)
	if buses.configure() != OK:
		_abort("AUDIO_MOVE_BUS_SETUP")
		return
	var index := AudioServer.get_bus_index(buses.sfx)
	AudioServer.set_bus_send(index, sink)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2
	AudioServer.add_bus_effect(index, capture)
	movement = AudioMove.new()
	add_child(movement)
	if movement.configure(Content.balance.audio, buses, true) != OK:
		_abort("AUDIO_MOVE_CONFIGURE")
		return
	movement.failed.connect(func(category: String, operation: String, error: Error) -> void:
		failures.append({"category": category, "operation": operation, "error": error}))
	movement.unlock(buses.context_seconds())
	movement.set_move("stomp", 1, 0, 1, 1)
	if not movement.voices.is_empty() or movement.bank != null or movement.thread.is_started():
		_abort("AUDIO_MOVE_LOW_POWER_ALLOCATED")
		return
	movement.set_low_power(false)
	for category: String in Content.balance.audio.scene.categories:
		movement.set_move(category, .8, 0, 1, 0)
	if not await _wait_rendered():
		_abort("AUDIO_MOVE_STREAM_START " + JSON.stringify(failures))
		return
	var identities := {}
	for category: String in movement.voices:
		identities[category] = movement.voices[category].get_instance_id()
	var before := _snapshots()
	# Source Web Audio continues while the UI thread stalls; this must too.
	OS.delay_msec(150)
	var after := _snapshots()
	for category: String in before:
		if int(after[category].frames) - int(before[category].frames) < int(AudioServer.get_mix_rate() * .08) or int(after[category].output_skips) != 0:
			_abort("AUDIO_MOVE_UI_STALL " + category)
			return
	var frames := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	for frame: Vector2 in frames:
		energy += frame.length_squared()
	if frames.is_empty() or energy / frames.size() <= .00000001:
		_abort("AUDIO_MOVE_CAPTURE_SILENT")
		return
	movement.set_move("stomp", .8, .4, 1, 1)
	await get_tree().create_timer(.5, true, false, true).timeout
	var wet: Dictionary = movement.voices.stomp.mixer.snapshot()
	if float(wet.get("wet", 0)) < .9:
		_abort("AUDIO_MOVE_WET_TARGET")
		return
	movement.set_low_power(true)
	await get_tree().create_timer(.4, true, false, true).timeout
	var quiet := _snapshots()
	movement.set_low_power(false)
	for category: String in Content.balance.audio.scene.categories:
		movement.set_move(category, .8, 0, 1, 0)
	await get_tree().create_timer(.3, true, false, true).timeout
	var resumed := _snapshots()
	for category: String in identities:
		if movement.voices[category].get_instance_id() != int(identities[category]) or float(quiet[category].gain) > .01 or int(resumed[category].frames) <= int(quiet[category].frames):
			_abort("AUDIO_MOVE_PERMANENT_CHANNEL " + category)
			return
	var graph: Dictionary = Content.balance.audio.moveGraphs.stomp
	var plan := AudioMovePlan.compile(graph)
	var frequency: float = plan.lfos.values()[0].frequency
	var elapsed := float(int(resumed.stomp.frames) - int(quiet.stomp.frames)) / AudioServer.get_mix_rate()
	var expected := fposmod(float(quiet.stomp.lfo_phase) + elapsed * frequency, 1)
	if absf(fposmod(float(resumed.stomp.lfo_phase) - expected + .5, 1) - .5) > .0001 or not failures.is_empty():
		_abort("AUDIO_MOVE_SHARED_PHASE " + JSON.stringify(failures))
		return
	results = {"before_stall": before, "after_stall": after, "wet": wet, "quiet": quiet, "resumed": resumed,
		"mean_energy": energy / frames.size(), "audibleAcceptanceRequired": true}
	var file := FileAccess.open("res://tests/audio-move-native.json", FileAccess.WRITE)
	if file == null:
		_abort("AUDIO_MOVE_CAPTURE_OUTPUT")
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	if not await _cleanup():
		push_error("AUDIO_MOVE_ROUTE_RETIREMENT_TIMEOUT")
		get_tree().quit(1)
		return
	print("AUDIO_MOVE_NATIVE_PASS nativeMixCaptured=true uiStallCovered=true audibleAcceptanceRequired=true")
	get_tree().quit()

func _wait_rendered() -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and failures.is_empty():
		var complete := movement.voices.size() == Content.balance.audio.scene.categories.size()
		for row: Dictionary in _snapshots().values():
			complete = complete and int(row.get("frames", 0)) > AudioServer.get_mix_rate() * .3
		if complete:
			return true
		await get_tree().create_timer(.025, true, false, true).timeout
	return false

func _snapshots() -> Dictionary:
	var result := {}
	for category: String in movement.voices:
		result[category] = movement.voices[category].mixer.snapshot()
	return result

func _cleanup() -> bool:
	if is_instance_valid(movement):
		movement.free()
	var names: Array[StringName] = []
	if is_instance_valid(buses):
		names = buses.owned.duplicate()
		buses.free()
	var deadline := Time.get_ticks_msec() + 2000
	while names.any(func(name): return AudioServer.get_bus_index(name) >= 0) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.02, true, false, true).timeout
	var index := AudioServer.get_bus_index(sink)
	if index > 0:
		AudioServer.remove_bus(index)
	return names.all(func(name): return AudioServer.get_bus_index(name) < 0)

func _abort(message: String) -> void:
	await _cleanup()
	push_error(message)
	get_tree().quit(1)
