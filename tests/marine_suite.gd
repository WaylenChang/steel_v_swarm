extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("marineRules") or not fixtures.has("marineWaveProgram") or not fixtures.has("marineRipplePrograms"):
		h._check(false, "Regenerate original marine wave packets and incremental swamp ripple programs")
		return
	var waves := MarineWaveSources.new()
	h._check(waves.configure(int(fixtures.marineRules.SEA_SOURCE_N)), "Bind original bounded sea-wave source buffers")
	for frame: Dictionary in fixtures.marineWaveProgram:
		waves.set_sources(frame.records)
		packets(h, waves.sources, frame.sources, "Original valid vessel-wave origins/headings, capacity and retained inactive slots")
		packets(h, waves.shapes, frame.shapes, "Original accepted vessel dimensions/speeds and zeroed inactive shapes")
	for sample: Dictionary in fixtures.marineRippleHashes:
		h._near(MarineRippleState.hash_value(int(sample.value)), sample.result, "Original unsigned imul swamp ripple hash")
	var previous := MarinePresentation.ripples
	for program: Dictionary in fixtures.marineRipplePrograms:
		MarinePresentation.ripples = MarineRippleState.new()
		var view := MarinePresentation.new()
		var mode: String = program.mode
		var water_state := {"value": program.bounds.waterY}
		var water := func(): return water_state.value
		var code := func(x: float, z: float):
			return 0 if mode == "dry" else 2 if (floori((x + 43) / 20) + floori((z + 61) / 20)) % 3 == 0 and (mode != "tidal" or float(water_state.value) > 0) else 1
		h._check(view.configure({"wind": fixtures.marineRules}, program.bounds, water, code), "Bind original six-frame swamp scanner and shared ripple state")
		var motions: Array[SceneryMotion] = []
		for frame: Dictionary in program.frames:
			water_state.value = frame.waterY
			view.advance(frame.delta, frame.now, {"waveAmp": frame.waveAmp}, motions)
			h._check(view.swamp_ready == frame.ready and view.swamp_cells == frame.cells and view.swamp_pending == frame.pending,
				"Original swamp scan row order, partial roster, dry/no-water skip and final readiness")
			if frame.nextZ != null:
				h._near(view.swamp_z, frame.nextZ, "Original swamp scan resumes at the next source row")
			h._check(MarinePresentation.ripples.index == int(frame.index), "Original one-emission-per-frame ripple slot rollover")
			h._near(MarinePresentation.ripples.cooldown, frame.cooldown, "Original ripple cooldown clamp, discarded overshoot and empty-roster hold")
			packets(h, MarinePresentation.ripples.packets, frame.packets, "Original deterministic ripple position, timestamp and amplitude")
		var saved_index := MarinePresentation.ripples.index
		var saved_cooldown := MarinePresentation.ripples.cooldown
		var saved_packets := MarinePresentation.ripples.packets.duplicate()
		h._check(MarinePresentation.ripples.configure(fixtures.marineRules), "Rebind original shared ripple declarations")
		h._check(MarinePresentation.ripples.index == saved_index and MarinePresentation.ripples.cooldown == saved_cooldown and MarinePresentation.ripples.packets == saved_packets,
			"Scene replacement retains original module-lifetime ripple slots/cooldown")
	MarinePresentation.ripples = previous

static func packets(h: Node, actual: PackedVector4Array, expected: Array, description: String) -> void:
	h._check(actual.size() == expected.size(), description + " capacity")
	for index in range(mini(actual.size(), expected.size())):
		var values: Array = expected[index]
		var packet := Vector4(values[0], values[1], values[2], values[3])
		h._check(actual[index].distance_to(packet) < 0.0001, description)
