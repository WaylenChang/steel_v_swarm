class_name RemoteShotState
extends RefCounted

static func plan(definition: Dictionary, slot: String, origin: Vector3, target: Vector3,
		hit: bool, bot: bool, clip: Callable) -> Dictionary:
	if slot == "heavy" and not definition.is_empty():
		if definition.area == "line":
			return {"kind": "lance", "target": clip.call(origin, target).to}
		if definition.type in ["launcher", "missile"] and origin.distance_squared_to(target) > .01:
			return {"kind": "shell", "target": target}
	var clipped: Dictionary = clip.call(origin, target)
	var ceiling := INF if definition.is_empty() else TargetingMath.maximum_range(definition) * float(Content.constants.RANGE_TOL)
	return {"kind": "shot", "target": clipped.to,
		"impact": bot or (hit or bool(clipped.cut)) and origin.distance_to(clipped.to) <= ceiling}

static func echo(definition: Dictionary, origin: Vector3, target: Vector3, clip: Callable) -> Dictionary:
	var clipped: Dictionary = clip.call(origin, target)
	return {"target": clipped.to, "impact": bool(clipped.cut) and origin.distance_to(clipped.to) <= TargetingMath.maximum_range(definition) * float(Content.constants.RANGE_TOL)}

static func relay(origin: Vector3, direction: Vector3, arc: Dictionary = {}) -> Dictionary:
	return {"target": arc.aim, "speed": floorf(float(arc.speed) + .5)} if not arc.is_empty() else {
		"target": origin + direction * float(Content.balance.projectileVisual.relayDistance), "speed": null}

static func muzzle(candidates: Array, fallback: Vector3) -> Vector3:
	var point := fallback
	var best := INF
	for candidate: Dictionary in candidates:
		if candidate.get("self", false) or candidate.get("fx_only", false) or not candidate.get("muzzle") is Vector3:
			continue
		var position: Vector3 = candidate.position
		var distance := position.distance_squared_to(fallback)
		if distance < best:
			best = distance
			point = candidate.muzzle
	return point

static func aim_heavy(body: BodyRig, direction: Vector3) -> void:
	if body == null:
		return
	var rig: Dictionary = body.forms.get(body.form, {})
	var gun: Variant = rig.get("gunL") if rig.get("weap", {}).get("heavy") == "L" else rig.get("gunR")
	if not gun is Dictionary:
		return
	if gun.get("aim0") == null:
		gun.aim0 = gun.get("aim", NAN)
	var horizontal := Vector2(direction.x, direction.z).length()
	gun.aim = float(gun.aim0) - atan2(direction.y, horizontal if horizontal != 0 else 1.0)
