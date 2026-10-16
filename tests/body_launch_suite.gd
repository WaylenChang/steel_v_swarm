extends RefCounted

static func frame(h: Node, body: BodyRig, step: Dictionary) -> void:
	if not step.has("muzzles"):
		h._check(false, "Regenerate original animated TPS muzzle references")
		return
	for item: Dictionary in step.muzzles:
		var marker: Dictionary = body.forms[body.form].get("muzzles", {}).get(item.slot, {})
		var had := marker.has("fxOnly")
		var saved: Variant = marker.get("fxOnly")
		if item.forceFallback and not marker.is_empty():
			marker.fxOnly = true
		var direction: Variant = null if item.direction == null else BodyPose.vector(item.direction)
		var result := BodyLaunchPose.resolve(body, item.slot, BodyPose.vector(step.position), item.eye, item.bodyYaw,
			BodyPose.vector(item.camera), item.reach, direction)
		compare(h, result, item.result, "Original animated TPS next-emitter/fallback camera convergence")
		if item.forceFallback and not marker.is_empty():
			if had:
				marker.fxOnly = saved
			else:
				marker.erase("fxOnly")

static func compare(h: Node, actual: Dictionary, expected: Dictionary, label: String) -> void:
	h._check(actual.origin.distance_to(BodyPose.vector(expected.origin)) < .0002, label + " origin")
	if expected.direction == null:
		h._check(actual.direction == null, label + " optional direction remains absent")
	else:
		h._check(actual.direction.distance_to(BodyPose.vector(expected.direction)) < .00002, label + " direction")
