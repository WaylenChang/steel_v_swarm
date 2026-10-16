extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")
const QuaternionTests = preload("res://tests/quaternion_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not Content.balance.bodyRules.has("gait") or not Content.balance.bodyRules.has("locomotion"):
		h._check(false, "Regenerate original gait/motion metadata")
		return
	for key: String in ["bodyDamping", "bodyCastDrive", "bodyJumpGates", "gaitPhases", "gaitDuties", "gaitHips", "gaitJoints", "gaitBounces", "gaitHumans", "gaitProfiles", "gaitLimbs", "bodyMotion", "bodyWeights"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original gait/motion oracle: " + key)
			return
	for item: Dictionary in fixtures.bodyDamping:
		h._near(BodyMotionState.friction(item.rate, item.delta), item.friction, "Original friction clamps negative rate/time")
		h._near(BodyMotionState.damp(2, -3, item.rate, item.delta), item.result, "Original shared body damping")
	for item: Dictionary in fixtures.bodyCastDrive:
		h._near(BodyCastPose.drive(item.value), item.result, "Original cast anticipation/overshoot/recovery phase curve")
	for item: Dictionary in fixtures.bodyJumpGates:
		var state: Dictionary = item.initial.duplicate(true)
		BodyJumpPose.step(BodyPose.new(), state, item.rig, item.entity, item.delta)
		Helper.compare(h, state, item.result, "Original absent-height/aerial/vehicle/morph jump handoff gates")
	for item: Dictionary in fixtures.gaitPhases:
		h._near(GaitCurves.cycle(item.value), item.result, "Original signed/wrapped gait phase")
	for item: Dictionary in fixtures.gaitDuties:
		h._near(GaitCurves.duty(item.key, item.gallop), item.result, "Original support/swing blend and duty limits")
	for item: Dictionary in fixtures.gaitHips:
		h._near(GaitCurves.hip(item.u, item.duty), item.result, "Original hip speed profile and eased stance edges")
	for item: Dictionary in fixtures.gaitJoints:
		h._near(GaitCurves.joint(item.role, int(item.index), item.u, item.duty), item.result, "Original proximal/distal joint curve and fallback role")
		h._near(GaitCurves.rest(item.role, int(item.index)), item.rest, "Original standing flex from the support-table midpoint")
	for item: Dictionary in fixtures.gaitBounces:
		h._near(GaitCurves.bounce(item.ph, item.duty, item.asym), item.result, "Original symmetric/asymmetric COM bounce")
	for item: Dictionary in fixtures.gaitHumans:
		Helper.compare(h, GaitCurves.human(item.u, item.duty), item.result, "Original human hip/arm phase tables")
	var profiles: Array = []
	for item: Dictionary in fixtures.gaitProfiles:
		var profile := GaitCurves.profile(item.spec)
		Helper.compare(h, profile, item.result, "Original fore/hind posture resolution and null/zero modifiers")
		profiles.append(profile)
	for item: Dictionary in fixtures.gaitLimbs:
		h._near(GaitCurves.limb(profiles[int(item.profile)][item.side], int(item.index), item.u, item.duty, item.amplitude), item.result,
			"Original support-only distal lock, reach and flex relative to the authored standing pose")
	for item: Dictionary in fixtures.bodyMotion:
		h._near(BodyMotionState.phase_of(item.id), item.phase, "Original stable UTF-16 entity phase hash")
		var state := BodyMotionState.new()
		state.configure(item.id)
		for step: Dictionary in item.steps:
			var before := state.values.duplicate(true)
			var frame := state.kinematics.duplicate(true)
			var advanced := state.advance(BodyPose.vector(step.position), step.yaw, BodyPose.vector(step.previous), step.previousYaw, step.delta)
			h._check(advanced == step.result.advanced, "Original hitstop/small-step gate")
			if advanced and item.walking:
				state.walk_rate(step.delta, item.reference)
			if step.result.state == null:
				h._check(state.values.is_empty(), "Frozen first frame does not initialize the gait state")
			else:
				Helper.compare(h, state.values, step.result.state, "Original position-difference velocity/acceleration and walk-clip state")
			if advanced:
				Helper.compare(h, state.kinematics, step.result.frame, "Original model-forward/lateral speed and shortest yaw rate")
			else:
				h._check(state.values == before and state.kinematics == frame, "Tiny/frozen step retains all prior motion state")
			if item.walking:
				var rate := float(state.values.get("ts", 1.0))
				h._near(rate, step.result.walk, "Original native animation playback rate including a frozen first frame")
	for item: Dictionary in fixtures.bodyWeights:
		var state: Variant = item.state.duplicate(true) if item.state is Dictionary else item.state
		var rig: Dictionary = item.rig.duplicate(true)
		if item.get("special") == "amp_nan":
			state.amp = NAN
		if item.get("special") == "amp_infinity":
			state.amp = INF
		if item.get("special") == "invalid_numbers":
			state.amp = NAN
			state.speed = INF
			rig._aim = NAN
		var actual := BodyMotionState.weights(state, rig, item.options)
		Helper.compare(h, actual, item.result, "Original ordered animation weights and first-finite priority")
		h._check(actual.keys() == Content.balance.bodyRules.locomotion.weights.keyOrder, "Animation consumers share the original ordered weight keys")
		h._near(float(actual.idle) + float(actual.walk) + float(actual.run), 1.0, "Original ground animation channels retain unit total weight")
		for value: float in actual.values():
			h._check(is_finite(value) and value >= 0 and value <= 1, "Invalid source inputs cannot leak nonfinite animation weights")
	JointTests.run(h, fixtures)
	QuaternionTests.run(h, fixtures)
