extends RefCounted

static func run(h: Node, metadata: Dictionary) -> void:
	if not metadata.has("synthesisIds"):
		h._check(false, "Regenerate original gain-independent synthesis stems")
		return
	var library := AudioSynthesisLibrary.new()
	library.configure(metadata)
	var references: Dictionary = Content.read_json("res://data/audio_probes.json")
	for probe: Dictionary in references.probes:
		var definition := library.definition(probe.id)
		if definition == null:
			h._check(false, "Import original native synthesis resource: " + str(probe.id))
			continue
		h._near(definition.reservation_seconds, probe.reservationSeconds, "Original synthesis reservation remains independent of native stem count")
		h._check(definition.source.audioSha256 == references.source.audioSha256 and definition.source.noiseSha256 == references.noise.sha256, "Synthesis stems retain the original module and shared private noise provenance")
		var rendered := library.render(probe.id, probe.gain)
		h._check(rendered.size() == definition.stems.size(), "All original independent amplitude envelopes produce native streams")
		if rendered.is_empty():
			continue
		for channel in range(2):
			var route := "panned" if channel == 0 else "centered"
			var actual := PackedFloat32Array()
			actual.resize(definition.frames)
			var tolerance := float(probe.channels[channel].maximumError) + .000003
			var needs_native_filter := false
			for stem: Dictionary in rendered:
				if stem.route != route:
					continue
				if not stem.effects.is_empty():
					needs_native_filter = true
					for captured: Dictionary in stem.effects:
						var filter := AudioSourceFilter.create(captured) as AudioEffectLowPassFilter
						h._check(filter != null, "Original post-envelope low-pass remains an explicit native effect")
						if filter != null:
							h._near(filter.resonance, pow(10.0, float(captured.parameters.Q.initial) / 20.0), "Web Audio decibel Q maps to native linear resonance")
					continue
				var bytes: PackedByteArray = stem.stream.data
				tolerance += float(stem.gain) / 65536.0
				for index in range(definition.frames):
					actual[index] += float(bytes.decode_s16(index * 2)) / 32768.0 * float(stem.gain)
			if needs_native_filter:
				continue
			var expected: Dictionary = probe.channels[channel]
			var bytes := Marshalls.base64_to_raw(expected.pcm)
			var maximum_error := 0.0
			for index in range(definition.frames):
				var value := float(bytes.decode_s16(index * 2)) / 32768.0 * float(expected.gain) if index < int(probe.frames) else 0.0
				maximum_error = maxf(maximum_error, absf(actual[index] - value))
			h._check(maximum_error <= tolerance, "Native per-sample gain envelopes match actual source output within independent PCM conversion bounds: " + str(probe.id) + "/" + route)
	var first := library.render("ui_click", 1.0)
	var repeated := library.render("ui_click", 1.0)
	var nearby := library.render("ui_click", 1.000001)
	if not first.is_empty() and not repeated.is_empty() and not nearby.is_empty():
		h._check(first[0].stream == repeated[0].stream and first[0].stream != nearby[0].stream, "Synthesis caching reuses exact gains without quantizing spatial attenuation")
	for index in range(library.capacity + 1):
		library.render("ui_click", .5 + float(index) / 1000.0)
	h._check(library.cache.size() <= library.capacity, "Native synthesized PCM cache remains bounded independently of its source definitions")
