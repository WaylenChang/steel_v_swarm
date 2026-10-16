class_name BodyMountAim
extends RefCounted

static func step(body: BodyRig, entity: Dictionary, delta: float, now: float, position: Vector3, yaw: float, nearest: Variant = null) -> void:
	var mounts := body.mounts
	var point: Variant = nearest
	var aim: Variant = entity.get("_aimAt")
	if aim is Dictionary and now < float(aim.until):
		point = Vector3(aim.x, aim.y, aim.z)
	var turret: Node3D = mounts.get("turret")
	if turret != null:
		var tower: bool = body.profile.kind == "tower"
		var wanted_yaw := 0.0
		var wanted_pitch := 0.0
		if point is Vector3:
			var offset: Vector3 = point - position
			wanted_yaw = atan2(offset.x, offset.z) if tower else wrap_angle(atan2(offset.x, offset.z) - yaw)
			var distance := Vector2(offset.x, offset.z).length()
			wanted_pitch = atan2(point.y + (2 if tower else 0) - turret.global_position.y, distance if tower or distance != 0 else 1.0)
		elif tower:
			wanted_yaw = body.poses.axis(turret, "y") + delta * 2
		var current := body.poses.axis(turret, "y")
		body.poses.set_axis(turret, "y", current + wrap_angle(wanted_yaw - current) * (1 - BodyMotionState.friction(4 if tower else 5, delta)))
		var pitch: Node3D = mounts.get("pitch")
		if pitch != null:
			var arc: Variant = entity.get("_arcPitch")
			if not tower and arc is Dictionary and now < float(arc.until):
				wanted_pitch = float(arc.v)
			wanted_pitch = clampf(wanted_pitch, -PI / 6, PI / 3)
			current = body.poses.axis(pitch, "x")
			body.poses.set_axis(pitch, "x", current + (-wanted_pitch - current) * (1 - BodyMotionState.friction(4, delta)))
	var tilt: Node3D = mounts.get("gunTilt")
	if tilt != null:
		var wanted := 0.0
		# The original aircraft mount follows shot memory only, without acquisition.
		if aim is Dictionary and now < float(aim.until):
			var distance := Vector2(float(aim.x) - position.x, float(aim.z) - position.z).length()
			wanted = clampf(atan2(float(aim.y) - tilt.global_position.y, distance if distance != 0 else 1.0), -1.1, .5)
		var current := body.poses.axis(tilt, "x")
		body.poses.set_axis(tilt, "x", current + (-wanted - current) * (1 - BodyMotionState.friction(4, delta)))
	var guns: Node3D = mounts.get("guns")
	if guns != null:
		for index in range(mounts.gunPivots.size()):
			var pivot: Node3D = mounts.gunPivots[index]
			var wanted_yaw := 0.0
			var wanted_pitch := -.14
			var gun_aim: Variant = entity.get("_gunAim", {}).get(index)
			if gun_aim is Dictionary and now < float(gun_aim.until):
				var offset := Vector3(gun_aim.x, gun_aim.y, gun_aim.z) - pivot.global_position
				wanted_yaw = wrap_angle(atan2(offset.x, offset.z) - body.poses.axis(guns, "y"))
				wanted_pitch = -clampf(atan2(offset.y, Vector2(offset.x, offset.z).length()), -PI / 6, PI / 3)
			var current := body.poses.axis(pivot, "y")
			body.poses.set_axis(pivot, "y", current + wrap_angle(wanted_yaw - current) * (1 - BodyMotionState.friction(3, delta)))
			var pitch: Node3D = mounts.gunPitches[index]
			current = body.poses.axis(pitch, "x")
			body.poses.set_axis(pitch, "x", current + (wanted_pitch - current) * (1 - BodyMotionState.friction(3, delta)))

static func shot_point(position: Vector3, ground: float, altitude: float, raised: bool, quantize: bool = true) -> Vector3:
	var height := (floorf(altitude + .5) if quantize else altitude) if raised else 0.0
	return Vector3(position.x, ground + height + float(Content.balance.bodyRules.presentation.shotHeight), position.z)

static func fallback_muzzle(position: Vector3, ground: float, height: float, target: Vector3, garrison: bool, override_y: Variant = null) -> Vector3:
	var rules: Dictionary = Content.balance.bodyRules.presentation
	if garrison:
		var offset := Vector2(target.x - position.x, target.z - position.z)
		var distance := offset.length()
		var direction := offset / (distance if distance != 0 else 1.0)
		return Vector3(position.x + direction.x * float(rules.garrisonRadius), ground + float(rules.garrisonHeight), position.z + direction.y * float(rules.garrisonRadius))
	return Vector3(position.x, ground + float(override_y) if override_y != null else position.y + height * float(rules.fallbackHeight), position.z)

static func nearest(state: Dictionary, position: Vector3, side: String, now: float, reach: float, candidates: Array, structures: bool = true) -> int:
	if float(state.get("_aimNext", 0)) == 0 or now >= float(state._aimNext):
		state._aimNext = now + float(Content.balance.bodyRules.presentation.nearestInterval)
		var best := 0
		var distance := reach
		for candidate: Dictionary in candidates:
			if candidate.side.is_empty() or candidate.side == side or candidate.neutral or candidate.dead:
				continue
			if candidate["static"] and not structures or not candidate.visible and not candidate["self"]:
				continue
			var target: Vector3 = candidate.position
			var measured := Vector2(target.x - position.x, target.z - position.z).length()
			if measured < distance:
				distance = measured
				best = int(candidate.id)
		state._aimTarget = best
	var id := int(state.get("_aimTarget", 0))
	return id if candidates.any(func(candidate): return int(candidate.id) == id) else 0

static func wrap_angle(angle: float) -> float:
	return atan2(sin(angle), cos(angle))
