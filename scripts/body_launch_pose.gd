class_name BodyLaunchPose
extends RefCounted

static func resolve(body: BodyRig, slot: String, position: Vector3, eye: float, body_yaw: float,
		camera: Vector3, reach: float, direction: Variant = null) -> Dictionary:
	var origin := body.next_muzzle(slot) if body != null else Vector3(NAN, NAN, NAN)
	if not origin.is_finite():
		var forward := Vector3(-sin(body_yaw), 0, -cos(body_yaw))
		origin = position + Vector3.UP * eye + forward * float(Content.balance.bodyRules.tpsMuzzleForward)
	var result := {"origin": origin, "direction": direction}
	if direction != null:
		assert(direction is Vector3, "TPS convergence requires the original camera direction")
		result.direction = SourceQuaternion.vector_normalized(camera + direction * reach - origin)
	return result
