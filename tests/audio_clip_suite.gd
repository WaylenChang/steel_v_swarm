extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node) -> void:
	if not Content.balance.get("audio", {}).has("nativeSamples") or not ResourceLoader.exists(AudioSampleLibrary.CATALOGUE_PATH):
		h._check(false, "Regenerate original decoded audio and import native clips")
		return
	var library := AudioSampleLibrary.new()
	h._check(library.load_samples(true) == OK and not library.loaded and library.catalogue == null and library.buffers.is_empty(), "Low-power registration does not read a native catalogue or retain decoded PCM")
	h._check(library.load_samples(false) == OK and library.loaded and library.catalogue != null, "Disabling low power registers source samples once")
	if library.catalogue == null:
		return
	var data: Dictionary = Content.read_json("res://data/audio_clips.json")
	Helper.compare(h, library.catalogue.source, data.source, "Native audio catalogue retains original module provenance")
	Helper.compare(h, library.catalogue.failures, data.failures, "Missing/undecodable source takes remain explicitly recorded for synthesis fallback")
	for id: String in data.samples:
		var expected: Array = data.samples[id]
		var actual: Array = library.buffers.get(id, [])
		h._check(actual.size() == expected.size(), "Decoded take order drops failures without inventing replacement samples: " + id)
		for index in range(mini(actual.size(), expected.size())):
			var clip: NativeAudioClip = actual[index]
			var source: Dictionary = expected[index]
			h._check(clip.valid() and clip.channel_count == source.channels.size() and clip.centered == null, "Original sample channels remain separate native mono resources")
			h._check(clip.source.url == source.url and clip.source.sha256 == source.sha256 and int(clip.source.take) == int(source.index), "Source sample identity survives failed-take compaction")
			h._near(clip.duration(), float(source.frames) / float(source.sampleRate), "Imported samples retain full decoded duration, including trailing silence")
			for channel in range(clip.panned.size()):
				var wave: AudioStreamWAV = clip.panned[channel]
				var captured: Dictionary = source.channels[channel]
				h._check(not wave.stereo and wave.mix_rate == int(source.sampleRate) and wave.data == Marshalls.base64_to_raw(captured.pcm), "Native PCM bytes and representation rate match the actual original decoder output conversion")
				h._near(clip.panned_gains[channel], captured.gain, "Captured normalization restores original channel peaks without clipping")
				for probe: Dictionary in captured.probes:
					var value := float(wave.data.decode_s16(int(probe.index) * 2)) / 32768.0 * clip.panned_gains[channel]
					h._check(absf(value - float(probe.value)) <= float(captured.maximumError) + .0000001, "Decoded source probe remains within the measured 16-bit conversion error")
			h._check(library.has_sample(id, false) and not library.has_sample(id, true), "Low-power selection bypasses previously loaded PCM without dropping the cache")
	var catalogue := library.catalogue
	var buffers := library.buffers.duplicate()
	h._check(library.load_samples(true) == OK and library.catalogue == catalogue and library.buffers == buffers, "Enabling low power keeps already loaded takes resident, as the source does")
	h._check(library.load_samples(false) == OK and library.catalogue == catalogue and library.buffers == buffers, "Repeated normal registration does not rebuild native sample resources")
	_synthesis_reference(h)
	_music(h)

static func _music(h: Node) -> void:
	var data: Dictionary = Content.read_json("res://data/audio_music.json")
	var resources := preload("res://scripts/audio_resource_snapshot.gd").new()
	h._check(data.get("formatVersion") == 1 and data.get("music", []).size() == 2, "Both original procedural arrangements are captured separately from real streaming BGM")
	for music: Dictionary in data.music:
		var clip := resources.music(music.mood)
		h._check(clip != null and clip.valid() and clip.channel_count == 0 and clip.centered != null, "Native procedural music retains the source centered routing")
		if clip == null or clip.centered == null:
			continue
		var stream: AudioStreamWAV = clip.centered
		h._check(clip.source.sha256 == data.source.audioSha256 and clip.source.noiseSha256 == data.noiseSha256, "Procedural arrangement provenance retains the original module and shared source noise realization")
		h._check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == int(music.loopBegin) and stream.loop_end == int(music.loopEnd), "Original intro plays once, with a complete steady arrangement including boundary tails retained in the native loop")
		h._check(stream.data == Marshalls.base64_to_raw(music.channels[0].pcm) and stream.mix_rate == int(music.sampleRate), "Native music PCM comes from actual original note/drum/oscillator/filter graphs")
		h._near(clip.centered_gain, music.channels[0].gain, "Procedural music retains normalization without clipping combined notes")
		h._near(float(stream.loop_end - stream.loop_begin) / stream.mix_rate, music.periodSeconds, "Integer native loop frames retain the exact source arrangement period without cumulative drift")
		h._check(int(music.cycleSteps) % (music.cfg.prog.size() * 16) == 0 and int(music.cycleSteps) % (music.cfg.scale.size() * 2) == 0, "Loop period includes the continuously advancing melody degree as well as chord progression")
		h._check(float(music.maximumLoopError) < .00002, "An additional original rendered period verifies waveform continuity across the retained loop")

static func _synthesis_reference(h: Node) -> void:
	var data: Dictionary = Content.read_json("res://data/audio_probes.json")
	h._check(data.get("formatVersion") == 1 and not data.probes.is_empty(), "Original synthesis probes remain available separately from playable sample assets")
	var bytes := Marshalls.base64_to_raw(data.noise.data)
	h._check(data.noise.encoding == "float32le" and bytes.size() == int(data.noise.frames) * 4, "All original synthesis probes share the captured private white-noise buffer")
	for probe: Dictionary in data.probes:
		h._check(probe.channels.size() == 2 and probe.reservationSeconds > 0 and not probe.graph.nodes.is_empty(), "Original synthesis keeps separate panned/centered outputs, voice time and actual AudioParam automation")
		for channel: Dictionary in probe.channels:
			h._check(Marshalls.base64_to_raw(channel.pcm).size() == int(probe.frames) * 2 and is_finite(float(channel.gain)), "Synthesis reference PCM is dimensioned and normalized without registering a generic runtime fallback")
