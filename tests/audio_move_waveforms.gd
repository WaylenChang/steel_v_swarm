extends Node

const Importer = preload("res://tools/audio_move_import.gd")
const PcmGain = preload("res://scripts/audio_pcm_gain.gd")
const PAD := 4096
var failures: Array[String] = []
var results: Array[Dictionary] = []
var movement: Dictionary
var reference: Dictionary
var buses: AudioBuses
var sink: StringName
var automation := false
var live := false

func _ready() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		push_error(message)
	return value

func _source() -> bool:
	var rate := int(AudioServer.get_mix_rate())
	automation = OS.get_cmdline_user_args().has("--automation")
	live = OS.get_cmdline_user_args().has("--live")
	if not _check(not live or automation, "Live command delivery requires an original automation corpus"):
		return false
	var directory := "audio_move_automation" if automation else "audio_move_waveforms"
	var scope := "original-movement-automation-waveforms" if automation else "original-movement-static-waveforms"
	reference = Content.read_json("res://data/%s/%d.json" % [directory, rate])
	if not _check(reference.get("scope") == scope and reference.get("sampleRate") == rate, "Original movement waveform archive matches the active device"):
		return false
	for entry: Dictionary in [reference.source.movementProfile, reference.source.contextProfile]:
		if not _check(FileAccess.get_sha256("res://" + str(entry.path)) == entry.sha256, "Movement waveform parent archive remains exact: " + str(entry.path)):
			return false
	for path: String in reference.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		if not _check(text.sha256_text() == reference.source.inputs[path], "Original waveform producer is current: " + path):
			return false
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in reference.source.sourceInputs:
		if not _check(provenance.inputs.get(path) == reference.source.sourceInputs[path], "Original waveform source matches imported provenance: " + path):
			return false
	movement = Content.read_json("res://" + str(reference.source.movementProfile.path))
	var keys: Array[String] = []
	for fixture: Dictionary in reference.waveforms:
		keys.append("%s:%.2f" % [fixture.category, fixture.wet])
		if not _check(fixture.frames == rate and fixture.channels.size() == 2, "Complete original stereo movement frames"):
			return false
		if automation:
			var counts := {"gain": 0, "pan": 0, "wet": 0, "rate": 0}
			for command: Dictionary in fixture.commands:
				if not _check(counts.has(command.key) and (command.key != "rate" or command.target == 1), "Original movement commands stay within the accepted automation scope"):
					return false
				counts[command.key] += 1
			if not _check(counts.gain == 4 and counts.pan == 3 and counts.wet == (3 if fixture.category == "stomp" else 0) and counts.rate > 0, "Complete original gain/pan/wet/stop command corpus"):
				return false
	keys.sort()
	return _check(movement.graphs == Content.balance.audio.moveGraphs and keys == ["engine:0.00", "rotor:0.00", "stomp:0.00", "stomp:0.65", "stomp:1.00", "wingflap:0.00"], "Complete original movement graph corpus")

func _pulse(generator: bool, route: StringName, owner: AudioMoveVoice) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = route
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	if generator:
		var stream := AudioGeneratorFeed.new()
		stream.configure(AudioServer.get_mix_rate())
		var values := PackedVector2Array()
		values.resize(16000)
		values.fill(Vector2.ZERO)
		for index in range(4):
			values[PAD + index] = Vector2.ONE * float([.5, -.5, 32767.0 / 32768.0, -.25][index])
		stream.playback.push_buffer(values)
		player.stream = stream
	else:
		var bytes := PackedByteArray()
		bytes.resize((PAD * 2 + 4) * 2)
		bytes.fill(0)
		for index in range(4):
			bytes.encode_s16((PAD + index) * 2, [16384, -16384, 32767, -8192][index])
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = int(AudioServer.get_mix_rate())
		stream.data = bytes
		player.stream = stream
		player.volume_linear = PcmGain.native_gain(stream, 1)
	owner.add_child(player)
	owner.input_players.append(player)
	return player

func _trace(frames: PackedVector2Array) -> int:
	for index in range(frames.size() - 3):
		var matches := true
		for offset in range(4):
			var value := float([.5, -.5, 32767.0 / 32768.0, -.25][offset])
			matches = matches and absf(frames[index + offset].x - value) <= .000001 and absf(frames[index + offset].y - value) <= .000001
		if matches:
			return index - PAD
	return -1

func _filter_l1(effect: Dictionary) -> float:
	for fixture: Dictionary in movement.filters:
		if fixture.effect.type == effect.type and fixture.effect.parameters == effect.parameters:
			var total := 0.0
			for value: float in fixture.responses[str(int(reference.sampleRate))]:
				total += absf(value)
			return total
	_check(false, "Source movement filter impulse exists")
	return NAN

func _bound(fixture: Dictionary, bank: NativeAudioMoveBank) -> float:
	var plan := AudioMovePlan.compile(movement.graphs[fixture.category])
	var modulation_error := 0.0
	for node: int in plan.lfos:
		modulation_error = float(reference.periodErrors[fixture.category + ":" + str(node)])
	var total := 0.0
	var maximum_gain := float(fixture.gain)
	for command: Dictionary in fixture.get("commands", []):
		if command.key == "gain":
			maximum_gain = maxf(maximum_gain, float(command.target))
	for branch: Dictionary in plan.branches:
		var l1 := 1.0
		for filter: Dictionary in branch.filters:
			l1 *= _filter_l1(filter.captured)
		var input_peak := float(reference.noisePeak) if branch.kind == "noise" else 1.0
		var error := bank.noise_gain / 65536.0 if branch.kind == "noise" else float(reference.periodErrors[fixture.category + ":" + str(branch.source)])
		error *= l1
		if not branch.modulation.is_empty():
			var peak := absf(float(branch.modulation.offset)) + absf(float(branch.modulation.depth))
			error = error * peak + input_peak * l1 * absf(float(branch.modulation.depth)) * modulation_error
		var weight := 1.0
		if branch.weight == "dry" and not automation:
			weight = 1.0 - float(fixture.wet)
		elif branch.weight == "wet" and not automation:
			weight = float(fixture.wet)
		total += (error + .000003) * absf(float(branch.gain)) * weight
	var panning := 1.0 if automation else maxf(AudioPan.mono_coefficients(float(fixture.pan)).x, AudioPan.mono_coefficients(float(fixture.pan)).y)
	return total * maximum_gain * panning

func _case(fixture: Dictionary, bank: NativeAudioMoveBank) -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3
	AudioServer.add_bus_effect(AudioServer.get_bus_index(buses.sfx), capture)
	var wav_trace := AudioEffectCapture.new()
	var gen_trace := AudioEffectCapture.new()
	wav_trace.buffer_length = 3
	gen_trace.buffer_length = 3
	var wav_route := buses.capture_bus([wav_trace])
	var gen_route := buses.capture_bus([gen_trace])
	var voice := AudioMoveVoice.new()
	add_child(voice)
	var configured := voice.configure(fixture.category, Content.balance.audio, bank, buses, fixture, 0)
	if not _check(configured == OK, "Configure original static movement graph"):
		voice.free()
		return
	_pulse(false, wav_route, voice)
	var generator_marker := _pulse(true, gen_route, voice)
	var native_failures: Array[String] = []
	voice.failed.connect(func(operation: String, error: Error): native_failures.append(operation + ":" + str(error)))
	var worker := AudioMoveWorker.new()
	var thread := Thread.new()
	var ready := [false]
	worker.started.connect(func(): ready[0] = true, CONNECT_DEFERRED)
	thread.start(worker.run)
	while not ready[0]:
		await get_tree().process_frame
	AudioServer.lock()
	capture.clear_buffer()
	wav_trace.clear_buffer()
	gen_trace.clear_buffer()
	AudioServer.unlock()
	_check(voice.activate() == OK, "Activate aligned movement inputs")
	var pending: Array[Dictionary] = []
	var deliveries: Array[Dictionary] = []
	for command: Dictionary in fixture.get("commands", []):
		if live:
			if command.key == "rate":
				_check(command.target == fixture.rate, "Live output-control corpus leaves the input rate unchanged")
			else:
				pending.append(command)
		else:
			voice.mixer.queue(command.key, command.target, command.tau, voice.mixer.origin + float(command.time))
	worker.add(voice.mixer)
	var deadline := Time.get_ticks_msec() + 1400
	while Time.get_ticks_msec() < deadline:
		var progress := voice.mixer.snapshot()
		while not pending.is_empty():
			var command: Dictionary = pending[0]
			var wanted := ceili(float(command.time) * float(reference.sampleRate))
			var frame := int(progress.get("frames", 0))
			# A published output cursor can lag the batch currently being mixed.
			# Enter the engine's observable input/output window, not that batch.
			if frame == 0 or (fixture.category == "engine" and wanted >= int(progress.get("input_frames", 0))):
				break
			deliveries.append({"key": command.key, "wanted": wanted, "outputFrame": frame, "inputFrame": progress.get("input_frames", 0)})
			voice.mixer.queue(command.key, command.target, command.tau, voice.mixer.origin + float(command.time))
			pending.pop_front()
		var feed := generator_marker.stream as AudioGeneratorFeed
		var silence := PackedVector2Array()
		silence.resize(feed.playback.get_frames_available())
		silence.fill(Vector2.ZERO)
		feed.playback.push_buffer(silence)
		await get_tree().create_timer(.001 if live else .01, true, false, true).timeout
	worker.stop()
	thread.wait_to_finish()
	var snapshot := voice.mixer.snapshot()
	_check(pending.is_empty(), "Deliver every original output command during native playback")
	if live and fixture.category == "engine":
		_check(deliveries.any(func(row: Dictionary): return row.wanted >= row.outputFrame and row.wanted < row.inputFrame), "Live engine controls enter after their input samples are already generated")
	var frames := capture.get_buffer(capture.get_frames_available())
	var wav_start := _trace(wav_trace.get_buffer(wav_trace.get_frames_available()))
	var gen_start := _trace(gen_trace.get_buffer(gen_trace.get_frames_available()))
	_check(native_failures.is_empty() and int(snapshot.get("output_skips", -1)) == 0, "Movement capture has no native buffer failures: " + JSON.stringify({"category": fixture.category, "snapshot": snapshot, "errors": native_failures}))
	_check(int(snapshot.get("late_control_frames", -1)) == 0, "Original movement commands reach their scheduled frames")
	_check(wav_start >= 0 and gen_start - wav_start == AudioGeneratorFeed.input_latency_frames(true) - AudioGeneratorFeed.input_latency_frames(false), "Independent native traces verify the engine input latency difference")
	var start := gen_start + voice.mixer.startup_frames
	if _check(start >= 0 and start + int(fixture.frames) <= frames.size(), "Independent output tracer covers every original source frame"):
		var maximum := 0.0
		var worst := 0
		for channel in range(2):
			var expected := Marshalls.base64_to_raw(fixture.channels[channel]).to_float32_array()
			for index in range(int(fixture.frames)):
				var actual := frames[start + index].x if channel == 0 else frames[start + index].y
				var error := absf(actual - expected[index])
				if error > maximum:
					maximum = error
					worst = index
		var result := {"category": fixture.category, "wet": fixture.wet, "frames": fixture.frames,
			"maximumError": maximum, "tolerance": _bound(fixture, bank), "worst": worst,
			"wavStart": wav_start, "generatorStart": gen_start, "start": start, "deliveries": deliveries,
			"lateControlFrames": snapshot.get("late_control_frames", -1),
			"startupBudgetFrames": voice.mixer.startup_budget_frames, "startupHistoryFrames": voice.mixer.startup_history_frames}
		results.append(result)
		_check(maximum <= float(result.tolerance), "Native complete movement waveform: " + JSON.stringify(result))
	voice.free()
	buses.release_voice(wav_route)
	buses.release_voice(gen_route)
	AudioServer.remove_bus_effect(AudioServer.get_bus_index(buses.sfx), 1)
	await get_tree().create_timer(.1, true, false, true).timeout

func _run() -> void:
	if not _source():
		get_tree().quit(1)
		return
	var bank := Importer.build(movement, movement.source, movement.graphs)
	if not _check(bank != null, "Build the original device-rate movement bank"):
		get_tree().quit(1)
		return
	AudioServer.add_bus()
	sink = StringName("MoveWaveformSink_%d" % get_instance_id())
	AudioServer.set_bus_name(AudioServer.bus_count - 1, sink)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(sink), true)
	buses = AudioBuses.new()
	add_child(buses)
	_check(buses.configure() == OK, "Configure private muted waveform routing")
	AudioServer.set_bus_send(AudioServer.get_bus_index(buses.sfx), sink)
	for fixture: Dictionary in reference.waveforms:
		await _case(fixture, bank)
	var prefix := "SVS_%d_" % buses.get_instance_id()
	buses.free()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		var remaining := false
		for index in range(AudioServer.bus_count):
			remaining = remaining or str(AudioServer.get_bus_name(index)).begins_with(prefix)
		if not remaining:
			break
		await get_tree().create_timer(.02, true, false, true).timeout
	for index in range(AudioServer.bus_count):
		_check(not str(AudioServer.get_bus_name(index)).begins_with(prefix), "Movement routes drain after native waveform capture")
	AudioServer.remove_bus(AudioServer.get_bus_index(sink))
	DirAccess.make_dir_recursive_absolute("res://artifacts/sol")
	var label := "audio-move-automation-live-native" if live else ("audio-move-automation-native" if automation else "audio-move-waveforms-native")
	var file := FileAccess.open("res://artifacts/sol/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"sampleRate": reference.sampleRate, "cases": results, "failures": failures}, "\t"))
	file.close()
	print("AUDIO_MOVE_AUTOMATION_LIVE" if live else ("AUDIO_MOVE_AUTOMATION" if automation else "AUDIO_MOVE_WAVEFORMS"), " cases=", results.size(), " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
