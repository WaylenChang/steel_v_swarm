class_name DeathSequenceState
extends RefCounted

var state: Dictionary = {}
var frame := Transform3D.IDENTITY
var output := Callable()
var random_sample := Callable()
var visual_random := RandomNumberGenerator.new()

func _init() -> void:
	visual_random.randomize()

func begin(seed: Dictionary, surface: Callable) -> bool:
	var eye: Transform3D = seed.eye
	var position: Vector3 = seed.position
	var velocity: Vector3 = seed.velocity
	var angles: Vector3 = seed.angles
	if not eye.origin.is_finite() or not position.is_finite() or not velocity.is_finite() or not angles.is_finite():
		push_error("Death sequence requires a finite live view")
		return false
	var ground := float(surface.call(position))
	if not is_finite(ground):
		push_error("Death sequence requires a verified standing surface")
		return false
	var flying: bool = seed.flying
	var duration := 2.4 if flying else 2.0
	var fall_time := duration - .55
	state = {"t": 0.0, "dur": duration, "fly": flying, "col": int(seed.color), "eye": eye.origin, "surf": ground,
		"g": minf(95, maxf(30, 2 * maxf(2, eye.origin.y - ground) / (fall_time * fall_time))) if flying else 0.0,
		"p": eye.origin, "v": velocity + Vector3.UP * 5 if flying else Vector3.ZERO,
		"yaw": angles.y, "pitch": angles.x, "roll": angles.z, "spin": Vector3.ZERO,
		"smokeAcc": 0.0, "climax": false, "holdUntil": 0.0, "fpvAcc": 0.0, "cut": false}
	if flying:
		state.spin = Vector3((_random() * 2 - 1) * 2.4, (_random() * 2 - 1) * 1.6,
			(-1 if _random() < .5 else 1) * (3 + _random() * 1.5))
	frame = eye
	_emit("alert", {"on": true, "flash": false})
	if flying:
		_emit("spark", {"point": eye.origin, "radius": 3.0, "color": 0xffb050})
	else:
		_emit("plume", {"point": Vector3(position.x, ground, position.z)})
	return true

func advance(delta: float, surface: Callable) -> void:
	if state.is_empty() or not is_finite(delta) or delta < 0:
		return
	var s := state
	s.t += delta
	var done := false
	if not s.fly:
		var decay := maxf(0, 1 - float(s.t) / .9)
		var n := decay * decay
		var shake_pitch := (_random() * 2 - 1) * n * .11
		var shake_yaw := (_random() * 2 - 1) * n * .11
		var shake_roll := (_random() * 2 - 1) * n * .13
		var progress := clampf((float(s.t) - .2) / 1.4, 0, 1)
		var topple := progress * progress * (3 - 2 * progress)
		var point: Vector3 = s.eye
		point.y = maxf(point.y - topple * 1.2, float(s.surf) + .4)
		_pose(point, float(s.yaw) + shake_yaw, float(s.pitch) + topple * .35 + shake_pitch, float(s.roll) + topple + shake_roll)
		s.smokeAcc += delta
		if float(s.smokeAcc) >= .22:
			s.smokeAcc = 0.0
			_emit("spark", {"point": Vector3(float(s.eye.x) + (_random() * 2 - 1) * 2,
				float(s.surf) + 1 + _random() * 2, float(s.eye.z) + (_random() * 2 - 1) * 2), "radius": 1.2, "color": 0xffb055})
		if not s.climax and float(s.t) >= 1.45:
			s.climax = true
			var at := Vector3(s.eye.x, s.surf, s.eye.z)
			_emit("explosion", {"point": at + Vector3.UP * 3, "radius": 11.0, "color": 0xff8a3a})
			_emit("shock", {"point": at, "radius": 10.0, "color": s.col})
			_emit("mechanical", {"point": at + Vector3.UP * 2, "big": true, "accent": s.col})
			_emit("comic", {"point": at + Vector3.UP * 9, "big": true, "hue": 18})
			_emit("plume", {"point": at})
			_emit("embers", {"point": at + Vector3.UP * 2, "count": 22, "spread": 7.0})
			_climax()
		done = float(s.t) >= float(s.dur)
	elif not s.climax:
		s.v.y -= float(s.g) * delta
		var drag := exp(-.7 * delta)
		s.v.x *= drag
		s.v.z *= drag
		s.p += s.v * delta
		s.yaw += float(s.spin.y) * delta
		s.pitch += float(s.spin.x) * delta
		s.roll += float(s.spin.z) * delta
		s.smokeAcc += delta
		if float(s.smokeAcc) > .06:
			s.smokeAcc = 0.0
			_emit("smoke", {"point": s.p, "size": 1.0})
		var point: Vector3 = s.p
		point.y = maxf(point.y, float(surface.call(s.p)) + .4)
		_pose(point, s.yaw, s.pitch, s.roll)
		var ground := float(surface.call(s.p))
		var hit_ground := float(s.p.y) <= ground + 1.6
		if hit_ground or float(s.t) >= float(s.dur) - .45:
			s.climax = true
			s.p.y = ground + 1 if hit_ground else float(s.p.y)
			_emit("explosion", {"point": s.p + Vector3.UP * 2, "radius": 13.0, "color": 0xff7a30})
			_emit("shock", {"point": s.p, "radius": 9.0, "color": s.col})
			_emit("mechanical", {"point": s.p + Vector3.UP, "big": true, "accent": s.col})
			_emit("plume", {"point": s.p})
			_emit("embers", {"point": s.p + Vector3.UP, "count": 22, "spread": 7.0})
			_climax()
			s.v = Vector3.ZERO
			s.holdUntil = float(s.t) + .45
	else:
		var gain := 1 - exp(-3 * delta)
		s.pitch += (-.5 - float(s.pitch)) * gain
		s.roll += -float(s.roll) * gain
		var point: Vector3 = s.p
		point.y = maxf(point.y, float(surface.call(s.p)) + .4)
		_pose(point, s.yaw, s.pitch, s.roll)
		s.smokeAcc += delta
		if float(s.smokeAcc) > .12:
			s.smokeAcc = 0.0
			_emit("smoke", {"point": s.p, "size": 1.6})
		done = float(s.t) >= float(s.holdUntil)
	s.fpvAcc += delta
	if float(s.fpvAcc) >= (.26 if s.climax else .12):
		s.fpvAcc = 0.0
		_emit("engulf", {"frame": frame})
	if done and not s.cut:
		s.cut = true
		_emit("cut", {"color": s.col})

func finish() -> void:
	state = {}
	_emit("alert", {"on": false, "flash": false})

func _climax() -> void:
	_emit("hitstop", {"seconds": .06})
	_emit("alert", {"on": true, "flash": true})

func _pose(point: Vector3, yaw: float, pitch: float, roll: float) -> void:
	var rotation := WeaponPresentation.source_rotation({"rotation": [pitch, yaw, roll], "order": "YXZ"})
	frame = Transform3D(SourceQuaternion.basis(rotation), point)

func _emit(type: String, data: Dictionary) -> void:
	if output.is_valid():
		output.call({"type": type}.merged(data))

func _random() -> float:
	return float(random_sample.call()) if random_sample.is_valid() else float(visual_random.randi()) / 4294967296.0
