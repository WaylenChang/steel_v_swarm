class_name NpcShotMotion
extends RefCounted

static func style(kind: String, override: Variant = null) -> Dictionary:
	var rules: Dictionary = Content.balance.npcShots
	if kind == "base":
		return rules.base
	if kind == "tower":
		return rules.tower
	var wid: String = str(override) if ControlPreferences.truthy(override) else str(Content.constants.UNITS.get(kind, {}).get("wid", ""))
	return rules.byWid.get(wid, rules.gun)

static func report_style(event: Dictionary, actor_kind: String) -> Dictionary:
	var reported: Variant = event.get("kind")
	var kind: String = str(reported) if ControlPreferences.truthy(reported) else actor_kind
	var override: Variant = event.get("wid")
	var wid: Variant = override if ControlPreferences.truthy(override) else Content.constants.UNITS.get(actor_kind, {}).get("wid")
	return {"kind": kind, "wid": wid, "style": style(kind, wid)}

static func clip(origin: Vector3, target: Vector3, obstruction: Callable) -> Dictionary:
	var hit: Dictionary = obstruction.call(origin, target)
	if hit.is_empty():
		return {"to": target, "cut": false}
	var distance := origin.distance_to(hit.position)
	var length := origin.distance_to(target)
	if length == 0:
		length = 1.0
	if distance >= length:
		return {"to": target, "cut": false}
	return {"to": origin.lerp(target, maxf(0, (distance - float(Content.balance.npcShots.clipBack)) / length)), "cut": true}

static func artillery(origin: Vector3, target: Vector3) -> Dictionary:
	var speed := float(Content.constants.BALLISTIC.LAUNCH_MV)
	var charges: Array = Content.constants.BALLISTIC.LOB_CHARGE
	for index in range(charges.size() - 1, -1, -1):
		var candidate := float(Content.constants.BALLISTIC.LAUNCH_MV) * float(charges[index])
		if LobFireControl.solve(origin, target, candidate).ok:
			speed = candidate
			break
	var velocity := LobFireControl.velocity(origin, target, speed)
	var distance := Vector2(target.x - origin.x, target.z - origin.z).length()
	var horizontal := Vector2(velocity.x, velocity.z).length()
	return {"velocity": velocity, "flight": (distance if distance != 0 else 1.0) / maxf(.001, horizontal),
		"angle": atan2(velocity.y, horizontal), "speed": speed}

static func prepare(kind: String, wid: Variant, origin: Vector3, requested: Vector3, collision: Callable,
		velocity: Variant = null, gravity: float = 0, flight: float = 0) -> Dictionary:
	var selected := style(kind, wid)
	var target := requested
	if selected.mode == "launch":
		return {"skip": false, "style": selected, "origin": origin, "target": target, "velocity": velocity, "gravity": gravity}
	if selected.mode == "shell" and velocity == null:
		flight = ShotHistory.flight_seconds({"trajectory": "lob"}, Vector2(target.x - origin.x, target.z - origin.z).length(), target.y - origin.y)
		if not flight > 0:
			return {"skip": true, "style": selected}
		gravity = float(Content.constants.BALLISTIC.G)
		velocity = (target - origin) / flight
		velocity.y += gravity * flight * .5
	if velocity == null and collision.is_valid():
		target = collision.call(origin, target).to
	var result := {"skip": false, "style": selected, "origin": origin, "target": target, "velocity": velocity, "gravity": gravity}
	if selected.mode in ["gun", "cannon", "beam", "launch"]:
		return result
	var length := origin.distance_to(target)
	if length < .01:
		result.skip = true
		return result
	var selected_wid: String = str(wid) if ControlPreferences.truthy(wid) else str(Content.constants.UNITS.get(kind, {}).get("wid", ""))
	var mv: Variant = Content.constants.WEAPONS.get(selected_wid, {}).get("mv")
	var travel := flight if velocity != null else length / maxf(1, float(mv) if ControlPreferences.truthy(mv) else 240.0)
	if not is_finite(travel) or travel <= 0:
		result.skip = true
		return result
	var stop := 1.0
	var previous := origin
	if velocity != null and collision.is_valid():
		for index in range(1, 9):
			var time := travel * index / 8.0
			var point: Vector3 = origin + velocity * time
			point.y -= gravity * time * time * .5
			var clipped: Dictionary = collision.call(previous, point)
			if clipped.cut:
				stop = ((index - 1) + previous.distance_to(clipped.to) / maxf(.001, previous.distance_to(point))) / 8.0
				target = clipped.to
				break
			previous = point
	result.target = target
	result.length = length
	result.travel = travel
	result.stop = stop
	result.ttl = clampf(travel * stop, .08, .65)
	result.quaternion = SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(velocity if velocity != null else target - origin))
	return result

static func sample(state: Dictionary, age: float) -> Dictionary:
	var progress := clampf(age / float(state.ttl), 0, 1)
	var point: Vector3
	if state.velocity != null:
		var time := float(state.travel) * float(state.stop) * progress
		point = state.origin + state.velocity * time
		point.y -= float(state.gravity) * time * time * .5
		var direction: Vector3 = state.velocity
		direction.y -= float(state.gravity) * time
		if direction.length_squared() > .001:
			state.quaternion = SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(direction))
	else:
		var origin: Vector3 = state.origin
		point = origin.lerp(state.target, progress)
	return {"position": point, "quaternion": state.quaternion, "age": progress * float(state.ttl), "speed": float(state.length) / float(state.ttl)}

static func aim(body: BodyRig, entity: Dictionary, angle: float, now: float) -> void:
	var owner: Dictionary = body.forms.get(body.form, {})
	var gun: Variant = owner.get("gunR")
	if gun is Dictionary:
		var compensation: Variant = gun.get("comp")
		gun.aim = (float(compensation) if ControlPreferences.truthy(compensation) else 0.0) - angle
	elif body.mounts.get("pitch") != null:
		entity._arcPitch = {"v": angle, "until": now + float(Content.balance.npcShots.arcHold)}
