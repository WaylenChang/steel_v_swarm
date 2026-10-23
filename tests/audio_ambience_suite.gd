extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary, metadata: Dictionary) -> void:
	if not fixtures.has("audioAmbienceLifecycle") or not metadata.has("ambienceTiming"):
		h._check(false, "Regenerate original permanent ambience lifecycle references")
		return
	for program: Dictionary in fixtures.audioAmbienceLifecycle:
		var state := AudioAmbienceState.new()
		state.configure(metadata)
		var observed := {"created": 0, "urls": {}}
		state.registered.connect(func(id: String, url: String) -> void:
			observed.created += 1
			observed.urls[id] = url
		)
		for frame: Dictionary in program.frames:
			var action: Array = frame.action
			var value: Variant = action[1] if action.size() > 1 else null
			match action[0]:
				"query": state.set_ambience(value)
				"unlock": state.unlocked = true
				"low": state.low_power = value
				"enabled": state.enabled = value
				"dispose": state.dispose()
			var expected: Dictionary = frame.result
			h._check(observed.created == expected.created and state.beds.size() == expected.beds.size(), "Original ambience lazily allocates above its threshold and retains silent/low-power beds")
			for id: String in state.beds:
				var source: Dictionary = expected.beds[id]
				Helper.compare(h, state.beds[id].target, source.target, "Original first-match gains and base-only low-power targets")
				h._check(observed.urls[id] == source.url and source.sfx and not source.paused, "Source beds keep playing through the SFX channel until disposal")
				h._near(metadata.ambienceTiming.initialGain, source.initialGain, "Original initial ambience gain")
				h._near(metadata.ambienceTiming.timeConstant, source.tau, "Original per-bed target time constant")
			h._check(expected.plays == observed.created and expected.pauses == (observed.created if state.disposed else 0), "Original beds start once and pause only on disposal")
	_envelopes(h, fixtures, metadata)

static func _envelopes(h: Node, fixtures: Dictionary, metadata: Dictionary) -> void:
	if not fixtures.has("audioAmbienceEnvelope"):
		h._check(false, "Regenerate actual original AudioParam ambience envelope probes")
		return
	var definitions: Dictionary = {str(metadata.ambienceBase.id): metadata.ambienceBase}
	for definition: Dictionary in metadata.ambience:
		definitions[definition.id] = definition
	for fixture: Dictionary in fixtures.audioAmbienceEnvelope:
		var state := AudioAmbienceState.new()
		state.configure(metadata)
		state.unlocked = true
		var now := 0.0
		var event_index := 0
		for probe: Dictionary in fixture.probes:
			var time := float(probe.index) / float(fixture.sampleRate)
			while event_index < fixture.events.size() and float(fixture.events[event_index].time) <= time:
				var event: Dictionary = fixture.events[event_index]
				state.advance(float(event.time) - now)
				now = float(event.time)
				state.low_power = event.low
				state._ride(definitions[fixture.id], float(event.volume))
				event_index += 1
			state.advance(time - now)
			now = time
			h._check(absf(float(state.beds[fixture.id].gain) - float(probe.value)) < .00002, "Native control envelope follows actual original AudioParam output across interrupted targets and low-power changes")
		state.dispose()
