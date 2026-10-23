extends Node

func _ready() -> void:
	_import.call_deferred()

func _import() -> void:
	var data: Dictionary = Content.read_json("res://data/audio_clips.json")
	if data.get("formatVersion") != 1 or not data.get("samples") is Dictionary or not data.get("source") is Dictionary or not data.get("failures") is Dictionary:
		_fail("Regenerate original decoded source audio")
		return
	if DirAccess.make_dir_recursive_absolute("res://assets/audio/native") != OK and not DirAccess.dir_exists_absolute("res://assets/audio/native"):
		_fail("Cannot create native audio resource directory")
		return
	var catalogue := NativeAudioCatalogue.new()
	catalogue.source = data.source.duplicate(true)
	catalogue.failures = data.failures.duplicate(true)
	var count := 0
	for id: String in data.samples:
		if not id.is_valid_identifier() or not data.samples[id] is Array:
			_fail("Unsupported source sound identifier: " + id)
			return
		var paths: Array[String] = []
		for index in range(data.samples[id].size()):
			var sample: Dictionary = data.samples[id][index]
			var clip := _clip(id, sample)
			if clip == null:
				return
			var path := "res://assets/audio/native/%s_%03d.res" % [id, index]
			if ResourceSaver.save(clip, path, ResourceSaver.FLAG_COMPRESS) != OK:
				_fail("Cannot save native source audio: " + path)
				return
			paths.append(path)
			count += 1
		catalogue.sample_paths[id] = paths
	var synth_data: Dictionary = Content.read_json("res://data/audio_synth.json")
	if synth_data.get("formatVersion") != 1 or not synth_data.get("sounds") is Array or synth_data.get("source") != data.source:
		_fail("Regenerate original independent synthesis stems")
		return
	for sound: Dictionary in synth_data.sounds:
		if not str(sound.get("id", "")).is_valid_identifier():
			_fail("Invalid original synthesis identifier")
			return
		var synthesis := NativeAudioSynthesis.new()
		synthesis.sample_rate = int(sound.sampleRate)
		synthesis.frames = int(sound.frames)
		synthesis.reservation_seconds = float(sound.reservationSeconds)
		synthesis.maximum_gain = float(sound.maximumGain)
		synthesis.source = {"id": sound.id, "audioSha256": data.source.audioSha256, "noiseSha256": synth_data.noiseSha256}
		for captured: Dictionary in sound.stems:
			var stem := NativeAudioStem.new()
			var bytes := Marshalls.base64_to_raw(captured.values)
			if bytes.size() != synthesis.frames * 4:
				_fail("Captured synthesis stem byte count mismatch: " + str(sound.id))
				return
			stem.values = bytes.to_float32_array()
			stem.route = captured.route
			stem.envelope.assign(captured.envelope)
			stem.effects.assign(captured.effects)
			for effect: Dictionary in stem.effects:
				if AudioSourceFilter.create(effect) == null:
					_fail("Unsupported original post-envelope synthesis effect: " + str(sound.id))
					return
			synthesis.stems.append(stem)
		var path := "res://assets/audio/native/%s_synth.res" % sound.id
		if not synthesis.valid() or ResourceSaver.save(synthesis, path, ResourceSaver.FLAG_COMPRESS) != OK:
			_fail("Cannot save original synthesis stems: " + path)
			return
	var music_data: Dictionary = Content.read_json("res://data/audio_music.json")
	if music_data.get("formatVersion") != 1 or not music_data.get("music") is Array or music_data.get("source") != data.source:
		_fail("Regenerate original procedural music arrangements")
		return
	for music: Dictionary in music_data.music:
		if music.get("mood") not in ["menu", "battle"] or not music.get("channels") is Array or music.channels.size() != 1:
			_fail("Invalid captured original procedural music")
			return
		if not is_finite(float(music.get("maximumLoopError", INF))) or float(music.maximumLoopError) >= .00002:
			_fail("Original procedural arrangement does not repeat within capture precision")
			return
		var sample := music.duplicate(true)
		sample.url = "source://audio.js/_procTick/" + str(music.mood)
		sample.index = 0
		sample.sha256 = data.source.audioSha256
		var clip := _clip("music_" + str(music.mood), sample)
		if clip == null:
			return
		clip.channel_count = 0
		clip.centered = clip.panned[0]
		clip.centered_gain = clip.panned_gains[0]
		clip.panned.clear()
		clip.panned_gains.clear()
		clip.centered.loop_mode = AudioStreamWAV.LOOP_FORWARD
		clip.centered.loop_begin = int(music.loopBegin)
		clip.centered.loop_end = int(music.loopEnd)
		clip.source.layer = "procedural_music"
		clip.source.noiseSha256 = music_data.noiseSha256
		clip.source.arrangement = music.duplicate(true)
		clip.source.arrangement.erase("channels")
		if clip.centered.loop_begin <= 0 or clip.centered.loop_end != int(music.frames) or clip.centered.loop_end != clip.centered.loop_begin * 2 or not clip.valid():
			_fail("Invalid original procedural music loop: " + str(music.mood))
			return
		var path := "res://assets/audio/native/%s_fallback.res" % music.mood
		if ResourceSaver.save(clip, path, ResourceSaver.FLAG_COMPRESS) != OK:
			_fail("Cannot save original procedural music loop: " + path)
			return
	if not _movement(data.source):
		return
	if not catalogue.valid() or ResourceSaver.save(catalogue, AudioSampleLibrary.CATALOGUE_PATH, ResourceSaver.FLAG_COMPRESS) != OK:
		_fail("Cannot save native source audio catalogue")
		return
	print("Imported original audio takes: ", count, " synthesisProbesRemainReferenceOnly=true")
	get_tree().quit()

func _movement(provenance: Dictionary) -> bool:
	var data: Dictionary = Content.read_json("res://data/audio_move.json")
	if data.get("formatVersion") != 1 or data.get("source") != provenance or not data.get("noise") is Dictionary or not data.get("oscillators") is Array:
		_fail("Regenerate original movement noise and oscillator periods")
		return false
	var bank := NativeAudioMoveBank.new()
	bank.source = provenance.duplicate(true)
	bank.source.noiseSha256 = data.noiseSha256
	var bytes := Marshalls.base64_to_raw(data.noise.values)
	if bytes.size() != int(data.noise.frames) * 4 or int(data.noise.frames) != int(data.noise.sampleRate):
		_fail("Invalid original shared movement noise buffer")
		return false
	var stem := NativeAudioStem.new()
	stem.values = bytes.to_float32_array()
	stem.envelope.assign([{"operation": "setValueAtTime", "time": 0.0, "constant": 1.0}])
	var rendered := stem.render(1, int(data.noise.sampleRate))
	if rendered.is_empty():
		_fail("Cannot convert original movement noise to native PCM")
		return false
	bank.noise = rendered.stream
	bank.noise_gain = rendered.gain
	bank.noise.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bank.noise.loop_begin = 0
	bank.noise.loop_end = int(data.noise.frames)
	for captured: Dictionary in data.oscillators:
		var values := Marshalls.base64_to_raw(captured.values)
		if values.size() != int(captured.frames) * 4:
			_fail("Invalid original movement oscillator period")
			return false
		if not bank.oscillators.has(captured.category):
			bank.oscillators[captured.category] = {}
		bank.oscillators[captured.category][str(int(captured.node))] = values.to_float32_array()
	if not bank.valid() or ResourceSaver.save(bank, NativeAudioMoveBank.PATH, ResourceSaver.FLAG_COMPRESS) != OK:
		_fail("Cannot save original native movement audio bank")
		return false
	return true

func _clip(id: String, sample: Dictionary) -> NativeAudioClip:
	if not sample.get("channels") is Array or sample.channels.size() not in [1, 2] or float(sample.get("sampleRate", 0)) <= 0 or float(sample.get("frames", 0)) <= 0:
		_fail("Invalid captured source audio dimensions: " + id)
		return null
	if float(sample.sampleRate) != floorf(float(sample.sampleRate)) or float(sample.frames) != floorf(float(sample.frames)):
		_fail("Noninteger captured source audio dimensions: " + id)
		return null
	var clip := NativeAudioClip.new()
	clip.channel_count = sample.channels.size()
	clip.source = {"layer": "sample", "id": id, "url": sample.url, "take": sample.index, "sha256": sample.sha256,
		"sampleRate": sample.sampleRate, "frames": sample.frames}
	for channel: Dictionary in sample.channels:
		var wave := AudioStreamWAV.new()
		wave.format = AudioStreamWAV.FORMAT_16_BITS
		wave.mix_rate = int(sample.sampleRate)
		wave.data = Marshalls.base64_to_raw(channel.pcm)
		if wave.data.size() != int(sample.frames) * 2:
			_fail("Source audio PCM byte count mismatch: " + id)
			return null
		clip.panned.append(wave)
		clip.panned_gains.append(float(channel.gain))
	if not clip.valid():
		_fail("Invalid captured source audio clip: " + id)
		return null
	return clip

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
