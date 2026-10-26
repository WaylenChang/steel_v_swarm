extends Node

const Importer = preload("res://tools/audio_synthesis_import.gd")
const PAD := 4096
const TRACE_ERROR := 8.0 * 0.00000011920928955078125
const ENVELOPE_ERROR := .000003

class TracedVoice extends AudioVoice:
	var marker: AudioStreamWAV
	var marker_bus: StringName
	func _play() -> bool:
		routes.append(marker_bus)
		if not _player(marker, marker_bus, 1, 1):
			return false
		return super._play()

var buses: AudioBuses
var capture: AudioEffectCapture
var sink: StringName
var profile: Dictionary
var panning := Vector2.ZERO
var results: Array[Dictionary] = []
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		push_error(message)
	return value

func _source() -> bool:
	var rate := int(AudioServer.get_mix_rate())
	var path := "res://data/audio_sfx_rates/%d.json" % rate
	if not _check(FileAccess.file_exists(path), "Capture the original SFX profile for native rate " + str(rate)):
		return false
	profile = Content.read_json(path)
	if not _check(profile.get("scope") == "original-sfx-synthesis-rate-only" and profile.sampleRate == rate, "SFX profile context rate matches the native mixer"):
		return false
	var ids: Array = []
	for sound: Dictionary in profile.sounds:
		ids.append(sound.id)
	ids.sort()
	var expected: Array = Content.balance.audio.synthesisIds.duplicate()
	expected.sort()
	if not _check(ids == expected and profile.probes.size() == ids.size() * 4, "Complete source synthesis and gain corpus"):
		return false
	for id: String in ids:
		var gains: Array = []
		for probe: Dictionary in profile.probes:
			if probe.id == id:
				gains.append(float(probe.gain))
		gains.sort()
		if not _check(gains == [.06, .4, 1.0, 1.4], "Every original gain probe appears exactly once: " + id):
			return false
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path_name: String in profile.source.sourceInputs:
		if not _check(provenance.inputs.get(path_name) == profile.source.sourceInputs[path_name], "Original SFX input matches imported metadata: " + path_name):
			return false
	for path_name: String in profile.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path_name).replace("\r\n", "\n").replace("\r", "\n")
		if not _check(text.sha256_text() == profile.source.inputs[path_name], "Original SFX producer is current: " + path_name):
			return false
	var noise := Marshalls.base64_to_raw(profile.noise.data)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(noise)
	if not _check(hash.finish().hex_encode() == profile.noise.sha256 and noise.size() == int(profile.noise.frames) * 4, "Original shared noise bytes match the synthesis profile"):
		return false
	var mixer: Dictionary = Content.read_json("res://data/audio_mixer.json")
	if not _check(mixer.source.audioSha256 == profile.source.audioSha256, "Source panning and synthesis share the same original audio module"):
		return false
	for fixture: Dictionary in mixer.audioPan:
		if float(fixture.pan) == 0 and fixture.input.size() == 1 and float(fixture.input[0]) == 1:
			panning = Vector2(fixture.left, fixture.right)
	return _check(panning.x > 0 and panning.y > 0, "Original center-panning coefficients are available")

func _marker(rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	# Silence on both sides prevents the tracer's own EOF fade from altering its pulse.
	bytes.resize((PAD * 2 + 4) * 2)
	bytes.fill(0)
	for index in range(4):
		bytes.encode_s16((PAD + index) * 2, [16384, -16384, 32767, -8192][index])
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _filter_l1(effect: Dictionary) -> float:
	for fixture: Dictionary in profile.filters:
		if fixture.effect.type == effect.type and fixture.effect.parameters == effect.parameters:
			var total := 0.0
			for value: float in fixture.responses[str(int(profile.sampleRate))]:
				total += absf(value)
			return total
	_check(false, "Original post-envelope filter impulse is available")
	return NAN

func _case(definition: NativeAudioSynthesis, probe: Dictionary) -> void:
	var stems := definition.render(float(probe.gain))
	if not _check(stems.size() == definition.stems.size(), "Render complete source stems: " + str(probe.id)):
		return
	var marker_capture := AudioEffectCapture.new()
	marker_capture.buffer_length = 4
	var voice := TracedVoice.new()
	voice.marker = _marker(int(profile.sampleRate))
	voice.marker_bus = buses.capture_bus([marker_capture])
	add_child(voice)
	AudioServer.lock()
	capture.clear_buffer()
	marker_capture.clear_buffer()
	AudioServer.unlock()
	if not _check(voice.start_synthesis(stems, buses, 0) == OK, "Start the original synthesis and independent timing tracer"):
		voice.free()
		return
	var deadline := Time.get_ticks_msec() + 4000
	while is_instance_valid(voice) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.01, true, false, true).timeout
	if not _check(not is_instance_valid(voice), "Native SFX completes: " + str(probe.id)):
		voice.free()
		return
	await get_tree().create_timer(.08, true, false, true).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var trace := marker_capture.get_buffer(marker_capture.get_frames_available())
	var start := -1
	var pattern := [.5, -.5, 32767.0 / 32768.0, -.25]
	for index in range(trace.size() - 3):
		var matches := true
		for offset in range(4):
			matches = matches and absf(trace[index + offset].x - float(pattern[offset])) <= TRACE_ERROR \
				and absf(trace[index + offset].y - float(pattern[offset])) <= TRACE_ERROR
		if matches:
			start = index - PAD
			break
	if not _check(start >= 0 and start + int(probe.frames) <= frames.size(), "Independent PCM timing trace and complete source frames: " + str(probe.id)):
		return
	var tolerance := float(probe.channels[0].maximumError) * maxf(panning.x, panning.y) + float(probe.channels[1].maximumError)
	var routes := {}
	for stem: Dictionary in stems:
		var multiplier := maxf(panning.x, panning.y) if stem.route == "panned" else 1.0
		routes[stem.route] = multiplier
		for effect: Dictionary in stem.effects:
			multiplier *= _filter_l1(effect)
		tolerance += float(stem.gain) / 65536.0 * multiplier
	for multiplier: float in routes.values():
		tolerance += ENVELOPE_ERROR * multiplier
	var expected := []
	for channel: Dictionary in probe.channels:
		expected.append(Marshalls.base64_to_raw(channel.pcm))
	var maximum := 0.0
	var worst := 0
	for index in range(int(probe.frames)):
		var panned := float(expected[0].decode_s16(index * 2)) / 32768.0 * float(probe.channels[0].gain)
		var centered := float(expected[1].decode_s16(index * 2)) / 32768.0 * float(probe.channels[1].gain)
		var error := maxf(absf(frames[start + index].x - (panned * panning.x + centered)), absf(frames[start + index].y - (panned * panning.y + centered)))
		if error > maximum:
			maximum = error
			worst = index
	var result := {"id": probe.id, "gain": probe.gain, "frames": probe.frames, "start": start, "maximumError": maximum, "tolerance": tolerance, "worst": worst}
	results.append(result)
	_check(maximum <= tolerance, "Native source synthesis waveform: " + JSON.stringify(result))

func _cleanup() -> void:
	if not is_instance_valid(buses):
		return
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
		_check(not str(AudioServer.get_bus_name(index)).begins_with(prefix), "Native synthesis routes drain without orphan buses")
	var sink_index := AudioServer.get_bus_index(sink)
	if sink_index > 0:
		AudioServer.remove_bus(sink_index)

func _run() -> void:
	if not _source():
		get_tree().quit(1)
		return
	AudioServer.add_bus()
	sink = StringName("SfxMixSink_%d" % get_instance_id())
	AudioServer.set_bus_name(AudioServer.bus_count - 1, sink)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(sink), true)
	buses = AudioBuses.new()
	add_child(buses)
	if not _check(buses.configure() == OK, "Configure private native synthesis routing"):
		await _cleanup()
		get_tree().quit(1)
		return
	AudioServer.set_bus_send(AudioServer.get_bus_index(buses.sfx), sink)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 4
	AudioServer.add_bus_effect(AudioServer.get_bus_index(buses.sfx), capture)
	var definitions := {}
	for sound: Dictionary in profile.sounds:
		definitions[sound.id] = Importer.build(sound, {"id": sound.id, "audioSha256": profile.source.audioSha256, "noiseSha256": profile.noise.sha256})
	var selected := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--id="):
			selected = argument.trim_prefix("--id=")
	for probe: Dictionary in profile.probes:
		if selected.is_empty() or selected == probe.id:
			if _check(definitions.get(probe.id) != null, "Load complete captured synthesis: " + str(probe.id)):
				await _case(definitions[probe.id], probe)
	_check(results.size() == (profile.probes.size() if selected.is_empty() else 4), "Capture the complete requested source gain corpus")
	await _cleanup()
	DirAccess.make_dir_recursive_absolute("res://artifacts/sol")
	var file := FileAccess.open("res://artifacts/sol/audio-sfx-mix-native.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"sampleRate": profile.sampleRate, "cases": results, "failures": failures}, "\t"))
	file.close()
	print("AUDIO_SFX_MIX cases=", results.size(), " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
