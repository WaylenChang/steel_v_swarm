extends RefCounted

static func run(h: Node, fixtures: Dictionary, metadata: Dictionary) -> void:
	if not fixtures.has("audioMusicGain") or not metadata.has("proceduralMusic"):
		h._check(false, "Regenerate chronologically rendered original procedural gain probes")
		return
	for fixture: Dictionary in fixtures.audioMusicGain:
		var voices: Array[Dictionary] = []
		var active: Dictionary = {}
		var volume := float(metadata.bgmDefault)
		var cursor := 0
		for probe: Dictionary in fixture.probes:
			var now := float(probe.index) / float(fixture.sampleRate)
			while cursor < fixture.actions.size() and float(fixture.actions[cursor].time) <= now:
				var action: Dictionary = fixture.actions[cursor]
				var time: float = action.time
				match action.op:
					"start":
						if active.is_empty() or active.mood != action.value:
							if not active.is_empty():
								active.envelope.release(time)
							var envelope := AudioMusicEnvelope.new()
							envelope.configure(metadata, fixture.sampleRate)
							envelope.start(time, volume)
							active = {"mood": action.value, "envelope": envelope}
							voices.append(active)
					"volume":
						volume = float(action.value)
						if not active.is_empty():
							active.envelope.set_volume(time, volume)
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
			h._check(absf(gain - float(probe.value)) < .00002, "Native procedural music gain follows actual source ramp replacement, cancellation, restart overlap and delayed disconnection")
