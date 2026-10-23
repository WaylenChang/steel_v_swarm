extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary, metadata: Dictionary) -> void:
	if not fixtures.has("audioMusicLifecycle") or not metadata.has("musicTiming"):
		h._check(false, "Regenerate original streamed music lifecycle references")
		return
	for program: Dictionary in fixtures.audioMusicLifecycle:
		var profile := AudioPreferences.new()
		profile.configure(metadata)
		var state := AudioMusicState.new()
		state.configure(metadata, profile)
		var observed := {"sfxGain": null, "fallback": []}
		var trace := func(value: Dictionary) -> void:
			if value.op == "sfx_gain":
				# Source setters before AudioContext creation have no channel to change.
				if state.unlocked or observed.get("unlocking", false):
					observed.sfxGain = value.gain
			elif value.op in ["fallback_stop", "fallback_start"]:
				observed.fallback.append(value.duplicate())
		state.command.connect(trace)
		for frame: Dictionary in program.frames:
			observed.fallback = []
			var action: Array = frame.action
			var operation: String = action[0]
			var value: Variant = action[1] if action.size() > 1 else null
			match operation:
				"scene": state.set_scene(value)
				"unlock":
					observed.unlocking = true
					state.unlock()
					observed.unlocking = false
				"dispose": state.dispose()
				"low":
					state.low_power = value
					if state.unlocked and not value:
						state.register_current()
				"ready": state.ready(value)
				"error": state.failed(value)
				"ticks":
					for _tick in range(int(value)):
						state.fade_step()
				"grace": state.grace_elapsed()
				"bgm": profile.set_bgm(value)
				"sfx": profile.set_sfx(value)
				"bgm_on": profile.set_bgm_on(value)
				"master_on": profile.set_master_on(value)
			var actual := {"scene": state.scene, "unlocked": state.unlocked, "disposed": state.disposed, "low": state.low_power,
				"fading": state.fading, "grace": state.grace_scene != null, "sfxGain": observed.sfxGain,
				"tracks": state.tracks, "fallback": observed.fallback}
			Helper.compare(h, actual, frame.result, "Original lazy codecs, interrupted fades, retained tracks, grace cancellation and setter effect ordering: " + str(action))
		state.dispose()
		state.command.disconnect(trace)
