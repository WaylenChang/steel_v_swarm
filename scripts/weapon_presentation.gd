class_name WeaponPresentation
extends RefCounted

var motion: Dictionary
var sequences: Dictionary = {}
var clips: Dictionary = {}
var last_serial := -1
var last_fire_at := NAN
var last_slot := "light"
var aim_until := -1.0
var aim := 0.0
var hair_started_at := NAN
var hair_fired_at := NAN

func configure(profile: Dictionary) -> void:
	motion = profile.motion
	for form: String in motion:
		sequences[form] = {}
		clips[form] = {}
		for slot: String in motion[form].clips:
			var animation := Animation.new()
			animation.length = 1
			for track: Dictionary in motion[form].clips[slot].tracks:
				var index := animation.add_track(Animation.TYPE_VALUE)
				animation.value_track_set_update_mode(index, Animation.UPDATE_CONTINUOUS)
				for key: Array in track.keys:
					animation.track_insert_key(index, key[0], key[1])
			clips[form][slot] = animation
		for slot: String in motion[form].sequences:
			var count: int = motion[form].sequences[slot].size()
			var times: Array[float] = []
			times.resize(count)
			times.fill(NAN)
			sequences[form][slot] = {"index": -1, "times": times}

func fire(serial: int, slot: String, at: float) -> bool:
	if serial <= last_serial or not is_finite(at) or slot not in ["light", "heavy"]:
		return false
	last_serial = serial
	last_fire_at = at
	last_slot = slot
	aim_until = maxf(aim_until, at + 1.5)
	for form: String in motion:
		var state: Dictionary = sequences[form][slot]
		state.index = posmod(int(state.index) + 1, state.times.size())
		state.times[int(state.index)] = at
		var hair: Variant = motion[form].hair
		if slot == "light" and hair != null:
			if not is_finite(hair_fired_at) or at - hair_fired_at > hair.burstGap:
				hair_started_at = at
			hair_fired_at = at
	return true

func advance(delta: float, now: float) -> void:
	if delta <= 0:
		return
	var holding := now < aim_until
	aim += ((1.0 if holding else 0.0) - aim) * (1 - exp(-(9.0 if holding else 3.5) * delta))

func pose(form: String, now: float) -> Dictionary:
	var spec: Dictionary = motion[form]
	var result: Dictionary = spec.nodes.duplicate(true)
	for track: Dictionary in spec.tracks:
		var pulse := 0.0
		for emitter: Dictionary in track.emitters:
			var age: float = now - sequences[form][emitter.slot].times[int(emitter.index)]
			if is_finite(age) and age >= 0:
				pulse = maxf(pulse, exp(-7 * age) * (1.0 if emitter.slot == "heavy" else 0.45))
		result[track.node][track.channel][axis_index(track.axis)] = track.rest + track.amplitude * pulse
	# Authored clips override procedural receiver recoil before the final payload/finger post-pass.
	var clip: Dictionary = spec.clips[last_slot]
	var time: float = (now - last_fire_at - clip.lead) / clip.duration
	if is_finite(time) and time >= 0 and time < 1:
		var animation: Animation = clips[form][last_slot]
		for i in range(clip.tracks.size()):
			var track: Dictionary = clip.tracks[i]
			result[track.node][track.channel][axis_index(track.axis)] = animation.value_track_interpolate(i, time)
	for slot: String in spec.sequences:
		for i in range(spec.sequences[slot].size()):
			var payload: String = spec.sequences[slot][i].payload
			if not result.has(payload):
				continue
			var age: float = now - sequences[form][slot].times[i]
			var size := 0.001 if is_finite(age) and age >= 0 and age < spec.durations[slot] else 1.0
			result[payload].scale = [size, size, size]
	if spec.hair != null:
		var hair: Dictionary = spec.hair
		var age := now - hair_fired_at
		var elapsed := now - hair_started_at
		var active: bool = is_finite(age) and age >= 0 and age < hair.burstGap
		var size := 1.0 if active and elapsed >= hair.pluckDuration * 0.4 else 0.001
		result[hair.tuft].scale = [size, size, size]
		result[hair.index].rotation[0] = 0.0
		result[hair.middle].rotation[0] = pow(sin(PI * minf(1, age / 0.11)), 2) * 1.2 if active and elapsed >= hair.pluckDuration else 1.1 if active else 0.0
		result[hair.thumb].rotation[2] = -0.55 if active else 0.0
	if spec.archery and result.has("gun_recoil"):
		var age := now - last_fire_at
		var release := sin(PI * (age - 0.26) / 0.20) if is_finite(age) and age >= 0.26 and age < 0.46 else 0.0
		var size := 0.001 if last_slot == "light" and aim > 0.0001 and release > 0.45 else 1.0
		result.gun_recoil.scale = [size, size, size]
	return result

static func axis_index(axis: String) -> int:
	return {"x": 0, "y": 1, "z": 2}[axis]

static func source_rotation(spec: Dictionary) -> Quaternion:
	var angles: Array = spec.rotation
	var rotations := {"X": Quaternion(Vector3.RIGHT, angles[0]), "Y": Quaternion(Vector3.UP, angles[1]), "Z": Quaternion(Vector3.BACK, angles[2])}
	var result := Quaternion.IDENTITY
	for axis: String in spec.order:
		result *= rotations[axis]
	return result
