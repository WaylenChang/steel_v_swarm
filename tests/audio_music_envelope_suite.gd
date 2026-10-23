extends RefCounted

static func run(h: Node, fixtures: Dictionary, metadata: Dictionary) -> Dictionary:
	if not fixtures.has("audioMusicGain") or not metadata.has("proceduralMusic"):
		h._check(false, "Regenerate chronologically rendered original procedural gain probes")
		return {}
	var samples := 0
	var maximum_error := 0.0
	h._check(not fixtures.audioMusicGain.is_empty(), "Source music gain capture contains rendered cases")
	for case_index in fixtures.audioMusicGain.size():
		var fixture: Dictionary = fixtures.audioMusicGain[case_index]
		h._check(not fixture.probes.is_empty(), "Source music gain case contains sample probes")
		var voices: Array[Dictionary] = []
		var active: Dictionary = {}
		var volume := float(metadata.bgmDefault)
		var enabled := true
		var cursor := 0
		for probe: Dictionary in fixture.probes:
			var now := float(probe.index) / float(fixture.sampleRate)
			# Compare sample indices so JSON float parsing cannot delay a boundary action.
			while cursor < fixture.actions.size() and roundi(float(fixture.actions[cursor].time) * float(fixture.sampleRate)) <= int(probe.index):
				var action: Dictionary = fixture.actions[cursor]
				var time := roundi(float(action.time) * float(fixture.sampleRate)) / float(fixture.sampleRate)
				match action.op:
					"start":
						if active.is_empty() or active.mood != action.value:
							if not active.is_empty():
								active.envelope.release(time)
							var envelope := AudioMusicEnvelope.new()
							envelope.configure(metadata, fixture.sampleRate)
							envelope.start(time, volume, enabled)
							active = {"mood": action.value, "envelope": envelope}
							voices.append(active)
					"volume":
						volume = float(action.value)
						if not active.is_empty():
							active.envelope.set_volume(time, volume if enabled else 0.0)
					"enabled":
						enabled = bool(action.value)
						if not active.is_empty():
							active.envelope.set_volume(time, volume if enabled else 0.0)
					"stop":
						if not active.is_empty():
							active.envelope.release(time)
							active = {}
					"expire":
						for voice: Dictionary in voices:
							if voice.envelope.retirement_time <= time + .00000001:
								voice.envelope.disconnect_output()
				cursor += 1
			var gain := 0.0
			for voice: Dictionary in voices:
				gain += voice.envelope.value_at(now)
			var error := absf(gain - float(probe.value))
			maximum_error = maxf(maximum_error, error)
			samples += 1
			h._check(error < .00002, "Native procedural music gain case=%d sample=%d actual=%.9f source=%.9f" % [case_index, probe.index, gain, probe.value])
	return {"cases": fixtures.audioMusicGain.size(), "samples": samples, "maximumError": maximum_error}
