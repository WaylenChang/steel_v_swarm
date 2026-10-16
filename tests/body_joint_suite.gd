extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["eulerSamples", "bodyRotations", "bodyFlex", "bodySignatures", "bodyIdle", "bodyGuns", "bodyHeads", "bodyTails", "bodyWings", "bodySoftLimbs"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original joint/Euler oracle: " + key)
			return
	for item: Dictionary in fixtures.eulerSamples:
		Helper.compare(h, SourceEuler.from_quaternion(BodyPose.quaternion(item.q), item.order), item.result,
			"Original six Euler orders and native-precision gimbal callbacks")
	for item: Dictionary in fixtures.bodyRotations:
		var node := make_node(item.initial)
		var poses := BodyPose.new()
		poses.configure({0: node})
		for step: Dictionary in item.steps:
			if step.has("axis"):
				poses.set_axis(node, step.axis, step.value)
			if step.has("scale"):
				poses.set_scale(node, BodyPose.vector(step.scale))
			if step.has("position"):
				poses.set_position(node, BodyPose.vector(step.position))
			if step.has("quaternion"):
				var state := poses.read(node)
				poses.write(node, state.p, BodyPose.quaternion(step.quaternion), state.s)
			compare_node(h, poses, node, step.result, "Original accumulated Euler/reflection/zero-scale pose semantics")
		node.free()
	for item: Dictionary in fixtures.bodyFlex:
		var nodes: Dictionary = {}
		var chain: Array = item.spec.duplicate(true)
		for index in range(item.initial.size()):
			var node := make_node(item.initial[index])
			nodes[index] = node
			chain[index].g = node
		var poses := BodyPose.new()
		poses.configure(nodes)
		for step: Dictionary in item.steps:
			BodyGaitJoints.flex_chain(poses, chain, step.phase, item.amplitude, step.idle, step.now, step.load, step.hold, item.anatomy)
			for index in range(step.result.size()):
				compare_node(h, poses, nodes[index], step.result[index], "Original joint-axis anatomy/human mix and legacy arm flex")
		for node: Node3D in nodes.values():
			node.free()
	for item: Dictionary in fixtures.bodySoftLimbs:
		var nodes: Dictionary = {}
		var chain: Array = item.spec.duplicate(true)
		for index in range(item.initial.size()):
			var node := make_node(item.initial[index])
			nodes[index] = node
			chain[index].g = node
		var poses := BodyPose.new()
		poses.configure(nodes)
		for step: Dictionary in item.steps:
			if item.method == "softLeg":
				BodyGaitQuad.soft_leg(poses, chain, step.phase, step.amplitude, step.now, step.quest)
			else:
				BodyGaitQuad.tent_guard(poses, chain, step.now, int(step.index), step.phase, step.amplitude)
			for index in range(chain.size()):
				compare_node(h, poses, chain[index].g, step.result[index], "Original single/multiple-link support/search/guard tentacle")
		for node: Node3D in nodes.values():
			node.free()
	for item: Dictionary in fixtures.bodySignatures:
		Helper.compare(h, BodyGaitJoints.ground_signature({"moveSig": item.spec}), item.ground, "Original ground personality with nullish defaults")
		Helper.compare(h, BodyGaitJoints.flight_signature({"moveSig": item.spec}), item.flight, "Original hover/surge/flare/bank personality")
	for item: Dictionary in fixtures.bodyIdle:
		h._near(BodyGaitJoints.idle(item.amplitude), item.result, "Original continuous idle complement")
	for item: Dictionary in fixtures.bodyGuns:
		var node := make_node(item.initial)
		var poses := BodyPose.new()
		poses.configure({0: node})
		BodyGaitJoints.gun_pitch(poses, {"g": node, "rest": item.rest, "aim": item.aim}, item.aiming, item.kick, item.charge, {"gun": item.gun})
		compare_node(h, poses, node, item.result, "Original gun pitch, recoil and null-versus-zero heavy factor")
		node.free()
	for item: Dictionary in fixtures.bodyHeads:
		var head := make_node(item.initial.head)
		var neck: Node3D = make_node(item.initial.neck) if item.initial.neck != null else null
		var nodes := {0: head}
		if neck != null:
			nodes[1] = neck
		var poses := BodyPose.new()
		poses.configure(nodes)
		BodyGaitJoints.stabilize_head(poses, {"head": head, "neck": neck}, item.accumulated, item.idle, item.now, item.strength, item.scan)
		compare_node(h, poses, head, item.result.head, "Original head stabilization and idle scanning")
		if neck != null:
			compare_node(h, poses, neck, item.result.neck, "Original shared head/neck compensation")
			neck.free()
		head.free()
	for item: Dictionary in fixtures.bodyTails:
		var nodes: Dictionary = {}
		var segments: Array = []
		for index in range(item.initial.size()):
			var node := make_node(item.initial[index])
			nodes[index] = node
			segments.append(node)
		var poses := BodyPose.new()
		poses.configure(nodes)
		var state: Dictionary = {}
		for step: Dictionary in item.steps:
			state.ph = step.phase
			BodyGaitJoints.whip_tail(poses, segments, state, step.delta, step.amplitude, step.idle, step.now, step.yawRate,
				item.base, item.aim, item.curl, item.stiffness, item.sway)
			Helper.compare(h, state, step.state, "Original damped tail turn state")
			for index in range(segments.size()):
				compare_node(h, poses, segments[index], step.result[index], "Original delayed tail curl/aim/sway and zero stiffness")
		for node: Node3D in segments:
			node.free()
	for item: Dictionary in fixtures.bodyWings:
		var nodes: Dictionary = {}
		var wing: Dictionary = item.spec.duplicate(true)
		for key: String in item.initial:
			if item.initial[key] == null:
				wing[key] = null
				continue
			var node := make_node(item.initial[key])
			nodes[key] = node
			wing[key] = node
		var poses := BodyPose.new()
		poses.configure(nodes)
		for step: Dictionary in item.steps:
			BodyGaitAerial.wing(poses, wing, step.phase, step.amplitude, step.attack, item.additive)
			for key: String in nodes:
				compare_node(h, poses, nodes[key], step.result[key], "Original bird/membrane shoulder/elbow/wrist, additive and absolute poses")
		for node: Node3D in nodes.values():
			node.free()

static func make_node(spec: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.rotation_order = SourceEuler.ORDERS.find_key(spec.order)
	node.transform = Transform3D(SourceQuaternion.basis(BodyPose.quaternion(spec.q)).scaled_local(BodyPose.vector(spec.s)), BodyPose.vector(spec.p))
	node.set_meta("source_trs", {"p": spec.p, "q": spec.q, "s": spec.s, "r": spec.r})
	return node

static func compare_node(h: Node, poses: BodyPose, node: Node3D, expected: Dictionary, label: String) -> void:
	Helper.compare(h, poses.rotation(node), expected.r, label + "/logical Euler")
	var transform := Transform3D(SourceQuaternion.basis(BodyPose.quaternion(expected.q)).scaled_local(BodyPose.vector(expected.s)), BodyPose.vector(expected.p))
	h._check(node.transform.origin.distance_to(transform.origin) < .00001 and node.basis.x.distance_to(transform.basis.x) < .00001
		and node.basis.y.distance_to(transform.basis.y) < .00001 and node.basis.z.distance_to(transform.basis.z) < .00001, label + "/native transform")

static func compare_instances(h: Node, node: Node3D, matrices: Array, label: String) -> void:
	var mesh := node as MultiMeshInstance3D
	h._check(mesh != null and mesh.multimesh != null, label + "/native MultiMesh")
	if mesh == null or mesh.multimesh == null:
		return
	h._check(mesh.multimesh.instance_count == matrices.size(), label + "/instance count")
	for index in range(mini(mesh.multimesh.instance_count, matrices.size())):
		var matrix: Array = matrices[index]
		var expected := Transform3D(Basis(Vector3(matrix[0], matrix[1], matrix[2]), Vector3(matrix[4], matrix[5], matrix[6]),
			Vector3(matrix[8], matrix[9], matrix[10])), Vector3(matrix[12], matrix[13], matrix[14]))
		var actual := mesh.multimesh.get_instance_transform(index)
		h._check(actual.origin.distance_to(expected.origin) < .00001 and actual.basis.x.distance_to(expected.basis.x) < .00001
			and actual.basis.y.distance_to(expected.basis.y) < .00001 and actual.basis.z.distance_to(expected.basis.z) < .00001, label + "/instance matrix")

static func compare_frame(h: Node, node: Node3D, spec: Dictionary, label: String) -> void:
	var frame := Transform3D(SourceQuaternion.basis(BodyPose.quaternion(spec.quaternion)).scaled_local(BodyPose.vector(spec.scale)), BodyPose.vector(spec.position))
	h._check(node.position.distance_to(frame.origin) < .0002 and node.basis.x.distance_to(frame.basis.x) < .0002
		and node.basis.y.distance_to(frame.basis.y) < .0002 and node.basis.z.distance_to(frame.basis.z) < .0002, label + "/native transform")
	h._check(node.visible == spec.visible and int(node.get_parent().get_meta("source_id", -1)) == int(spec.parent), label + "/hierarchy and visibility")
	if spec.has("instances"):
		compare_instances(h, node, spec.instances, label)
