class_name BodyMorph
extends RefCounted

static func ease(progress: float) -> float:
	return 0.0 if progress <= 0 else 1.0 if progress >= 1 else progress * progress * (3 - 2 * progress)

static func rest_weight(progress: float) -> float:
	return clampf((0.5 - absf(progress - 0.5)) / float(Content.balance.bodyRules.morph.HALF), 0, 1)

static func alpha(progress: float, air: bool) -> float:
	return clampf((progress - 0.5 if air else 0.5 - progress) / float(Content.balance.bodyRules.morph.FADE), 0, 1)

static func shrink(opacity: float) -> float:
	var minimum: float = Content.balance.bodyRules.morph.SHRINK
	return minimum + (1 - minimum) * opacity

static func active(progress: float) -> bool:
	var epsilon: float = Content.balance.bodyRules.morph.EPS
	return progress > epsilon and progress < 1 - epsilon

static func slerp(first: Quaternion, second: Quaternion, weight: float) -> Quaternion:
	var dot := first.dot(second)
	if dot < 0:
		dot = -dot
		second = -second
	var left := 1 - weight
	var right := weight
	if dot <= float(Content.balance.bodyRules.morph.slerpDot):
		var angle := acos(dot)
		var sine := sin(angle)
		left = sin((1 - weight) * angle) / sine
		right = sin(weight * angle) / sine
	var result := first * left + second * right
	return result.normalized() if result.length_squared() != 0 else result

static func swap(rig: BodyRig, delta: float, altitude: float) -> void:
	var state: Dictionary = rig.morph
	if state.is_empty():
		return
	assert(state.get("plan") != null, "Missing original per-part morph plan")
	var wanted := 1.0 if altitude > float(Content.constants.MORPH.GROUND_Y) else 0.0
	var progress: float = state.get("m", wanted)
	state.m = BodyMotionState.damp(progress, wanted, Content.balance.bodyRules.morph.damping, delta)
	var air: bool = state.m >= 0.5
	if air != bool(state.air0):
		state.air0 = air
		state.ag.visible = air
		state.gg.visible = not air
		rig.form = "air" if air else "ground"
	state.k = rest_weight(state.m)

static func pose(rig: BodyRig) -> void:
	var state: Dictionary = rig.morph
	if state.is_empty():
		return
	assert(state.get("plan") != null, "Missing original per-part morph plan")
	var changing := active(state.m)
	if not changing and not state.act:
		return
	var progress: float = state.m if changing else 1.0 if state.m >= 0.5 else 0.0
	var weight := ease(progress)
	var settle := rest_weight(progress) if changing else 0.0
	_side(rig.poses, state.plan.g, weight, settle, alpha(progress, false))
	_side(rig.poses, state.plan.a, weight, settle, alpha(progress, true))
	state.act = changing

static func _side(poses: BodyPose, side: Dictionary, weight: float, settle: float, opacity: float) -> void:
	for pair: Dictionary in side.pairs:
		var position := BodyPose.vector(pair.A.p).lerp(BodyPose.vector(pair.B.p), weight)
		var rotation := slerp(BodyPose.quaternion(pair.A.q), BodyPose.quaternion(pair.B.q), weight)
		var size := BodyPose.vector(pair.A.s).lerp(BodyPose.vector(pair.B.s), weight)
		poses.write(pair.n, position, rotation, size)
	if settle > 0:
		for entry: Dictionary in side.rest:
			var current := poses.read(entry.n)
			poses.write(entry.n, current.p.lerp(BodyPose.vector(entry.r.p), settle),
				slerp(current.q, BodyPose.quaternion(entry.r.q), settle), current.s.lerp(BodyPose.vector(entry.r.s), settle))
	var rules: Dictionary = Content.balance.bodyRules.morph
	for entry: Dictionary in side.fade:
		if entry.a == opacity:
			continue
		entry.a = opacity
		entry.n.visible = bool(entry.v0) and opacity > float(rules.visibleAlpha)
		poses.set_scale(entry.n, BodyPose.vector(entry.s0) * shrink(opacity))
		for item: Dictionary in entry.mats:
			var restored := opacity >= float(rules.restoreAlpha)
			var transparent: bool = item.t0 if restored else true
			var depth: bool = item.d0 if restored else false
			var value: float = item.o0 if restored else float(item.o0) * opacity
			var material: Material = item.m
			material.set_meta("source_transparent", transparent)
			BodyMaterials.set_opacity(material, value)
			material.set_meta("source_depth_write", depth)
			if material is BaseMaterial3D:
				var native := material as BaseMaterial3D
				native.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if transparent else BaseMaterial3D.TRANSPARENCY_DISABLED
				native.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if depth else BaseMaterial3D.DEPTH_DRAW_DISABLED
			else:
				assert(material is ShaderMaterial and transparent and not depth, "Unsupported morph shader depth/transparency change")
