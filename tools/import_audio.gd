extends Node

const ResourcePublisher = preload("res://tools/source_resource_publisher.gd")
const ClipIdentity = preload("res://scripts/audio_clip_identity.gd")
const ResourceIdentity = preload("res://scripts/audio_resource_identity.gd")
const SynthesisImport = preload("res://tools/audio_synthesis_import.gd")
var catalogue_path := AudioSampleLibrary.CATALOGUE_PATH

func _ready() -> void:
	_import.call_deferred()

func _import() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument != "--samples-only":
			_fail("Unsupported audio import argument: " + argument)
			return
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
		var hashes: Array[String] = []
		for index in range(data.samples[id].size()):
			var sample: Dictionary = data.samples[id][index]
			var clip := _clip(id, sample)
			if clip == null:
				return
			var hash := ClipIdentity.digest(clip)
			var path := "res://assets/audio/native/%s_%s.res" % [id, hash]
			if FileAccess.file_exists(path):
				var existing := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NativeAudioClip
				if ClipIdentity.digest(existing) != hash:
					_fail("Existing content-addressed source clip is invalid: " + path)
					return
			elif await ResourcePublisher.publish(clip, path, get_tree()) != OK:
				_fail("Cannot save native source audio: " + path)
				return
			paths.append(path)
			hashes.append(hash)
			count += 1
		catalogue.sample_paths[id] = paths
		catalogue.sample_hashes[id] = hashes
	if OS.get_cmdline_user_args().has("--samples-only"):
		if not _retain_resources(catalogue):
			return
		await _publish_catalogue(catalogue, count)
		return
	var synth_data: Dictionary = Content.read_json("res://data/audio_synth.json")
	if synth_data.get("formatVersion") != 1 or not synth_data.get("sounds") is Array or synth_data.get("source") != data.source:
		_fail("Regenerate original independent synthesis stems")
		return
	var captured_ids := []
	for sound: Variant in synth_data.sounds:
		if not sound is Dictionary or not sound.get("id") is String:
			_fail("Invalid original synthesis identifier")
			return
		captured_ids.append(sound.id)
	var expected_ids: Array = Content.balance.audio.synthesisIds.duplicate()
	captured_ids.sort()
	expected_ids.sort()
	if captured_ids != expected_ids:
		_fail("Incomplete original synthesis resource set")
		return
	for sound: Dictionary in synth_data.sounds:
		if not str(sound.get("id", "")).is_valid_identifier() or catalogue.synthesis_ids.has(str(sound.id)):
			_fail("Invalid original synthesis identifier")
			return
		var synthesis := SynthesisImport.build(sound, {"id": sound.id, "audioSha256": data.source.audioSha256, "noiseSha256": synth_data.noiseSha256})
		if synthesis == null:
			_fail("Invalid captured source synthesis: " + str(sound.id))
			return
		for stem: NativeAudioStem in synthesis.stems:
			for effect: Dictionary in stem.effects:
				if AudioSourceFilter.create(effect) == null:
					_fail("Unsupported original post-envelope synthesis effect: " + str(sound.id))
					return
		if not await _publish_resource(catalogue, "synthesis_" + str(sound.id), synthesis):
			return
		catalogue.synthesis_ids.append(str(sound.id))
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
		if not await _publish_resource(catalogue, "music_" + str(music.mood), clip):
			return
	if not await _movement(data.source, catalogue):
		return
	catalogue.complete_resources = true
	await _publish_catalogue(catalogue, count)

func _retain_resources(catalogue: NativeAudioCatalogue) -> bool:
	if not FileAccess.file_exists(catalogue_path):
		return true
	var previous := ResourceLoader.load(catalogue_path, "", ResourceLoader.CACHE_MODE_IGNORE) as NativeAudioCatalogue
	if previous == null:
		_fail("Cannot read the previous native audio catalogue")
		return false
	if not previous.complete_resources:
		return true
	if not previous.valid() or previous.source != catalogue.source:
		_fail("Samples-only import requires the same complete source catalogue; run the full audio importer")
		return false
	for key: String in previous.resource_paths:
		var path: String = previous.resource_paths[key]
		var stored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if ResourceLoader.exists(path) else null
		if stored == null or ResourceIdentity.digest(stored) != previous.resource_hashes[key]:
			_fail("Missing or invalid retained native audio resource: " + path)
			return false
	catalogue.complete_resources = true
	catalogue.synthesis_ids = previous.synthesis_ids.duplicate()
	catalogue.resource_paths = previous.resource_paths.duplicate()
	catalogue.resource_hashes = previous.resource_hashes.duplicate()
	return true

func _publish_resource(catalogue: NativeAudioCatalogue, key: String, resource: Resource) -> bool:
	var hash := ResourceIdentity.digest(resource)
	if not key.is_valid_identifier() or hash.is_empty() or catalogue.resource_paths.has(key):
		_fail("Invalid/duplicate original audio resource: " + key)
		return false
	var path := "res://assets/audio/native/%s_%s.res" % [key, hash]
	if not FileAccess.file_exists(path):
		if await ResourcePublisher.publish(resource, path, get_tree()) != OK:
			_fail("Cannot publish original audio resource: " + path)
			return false
	var stored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if stored == null or ResourceIdentity.digest(stored) != hash:
		_fail("Existing content-addressed original audio resource is invalid: " + path)
		return false
	catalogue.resource_paths[key] = path
	catalogue.resource_hashes[key] = hash
	return true

func _publish_catalogue(catalogue: NativeAudioCatalogue, count: int) -> void:
	if not catalogue.valid() or await ResourcePublisher.publish(catalogue, catalogue_path, get_tree()) != OK:
		_fail("Cannot save native source audio catalogue")
		return
	print("Imported original audio takes: ", count, " synthesisProbesRemainReferenceOnly=true")
	get_tree().quit()

func _movement(provenance: Dictionary, catalogue: NativeAudioCatalogue) -> bool:
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
		var node := str(int(captured.node))
		if bank.oscillators[captured.category].has(node):
			_fail("Duplicate original movement oscillator period")
			return false
		bank.oscillators[captured.category][node] = values.to_float32_array()
	if bank.oscillators.size() != Content.balance.audio.moveGraphs.size():
		_fail("Unexpected original movement oscillator category")
		return false
	for category: String in Content.balance.audio.moveGraphs:
		var expected := []
		for node: Dictionary in Content.balance.audio.moveGraphs[category].nodes:
			if node.kind == "createOscillator":
				expected.append(str(int(node.id)))
		var actual: Array = bank.oscillators.get(category, {}).keys()
		expected.sort()
		actual.sort()
		if actual != expected:
			_fail("Incomplete original movement oscillator periods: " + category)
			return false
	return await _publish_resource(catalogue, "movement", bank)

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
