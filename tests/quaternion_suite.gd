extends RefCounted

const JointTests = preload("res://tests/body_joint_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["quaternionOps", "quaternionSlerps", "quaternionDirections", "quaternionMatrices", "quaternionWorlds"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original quaternion/world-frame oracle: " + key)
			return
	for item: Dictionary in fixtures.quaternionOps:
		var first := BodyPose.quaternion(item.first)
		var second := BodyPose.quaternion(item.second)
		compare(h, SourceQuaternion.normalized(first), item.normalized, "Original quaternion normalization including zero")
		compare(h, SourceQuaternion.inverse(first), item.inverse, "Original conjugate-only inverse")
		compare(h, SourceQuaternion.multiply(first, second), item.product, "Original quaternion product")
		var point := SourceQuaternion.rotate(first, BodyPose.vector(item.point))
		h._check(point.distance_to(BodyPose.vector(item.rotated)) < .00001, "Original vector rotation including non-unit quaternions")
		var basis := SourceQuaternion.basis(first)
		var expected := frame(item.matrix).basis
		h._check(basis.x.distance_to(expected.x) < .00001 and basis.y.distance_to(expected.y) < .00001
			and basis.z.distance_to(expected.z) < .00001, "Original non-unit quaternion matrix composition")
	for item: Dictionary in fixtures.quaternionSlerps:
		compare(h, SourceQuaternion.slerp(BodyPose.quaternion(item.first), BodyPose.quaternion(item.second), item.weight), item.result,
			"Original exact slerp endpoints, hemisphere, non-unit and extrapolation branches")
	for item: Dictionary in fixtures.quaternionDirections:
		compare(h, SourceQuaternion.from_unit_vectors(BodyPose.vector(item.first), BodyPose.vector(item.second)), item.result,
			"Original unit-vector arc and antiparallel axis selection")
	for item: Dictionary in fixtures.quaternionMatrices:
		compare(h, SourceQuaternion.from_basis(frame(item.matrix).basis), item.result,
			"Original mirrored/nonuniform/sheared/singular matrix rotation extraction")
	for item: Dictionary in fixtures.quaternionWorlds:
		var nodes: Array[Node3D] = []
		for spec: Dictionary in item.nodes:
			var node := JointTests.make_node(spec)
			if nodes.is_empty():
				h.add_child(node)
			else:
				nodes.back().add_child(node)
			nodes.append(node)
		for index in range(nodes.size()):
			var node: Node3D = nodes[index]
			var expected := frame(item.result[index].matrix)
			h._check(node.global_transform.origin.distance_to(expected.origin) < .00002 and node.global_basis.x.distance_to(expected.basis.x) < .00002
				and node.global_basis.y.distance_to(expected.basis.y) < .00002 and node.global_basis.z.distance_to(expected.basis.z) < .00002,
				"Original complete hierarchy world frame")
			compare(h, SourceQuaternion.world(node), item.result[index].quaternion, "Original hierarchy quaternion without orthonormalizing shear", .00001)
		nodes[0].free()

static func compare(h: Node, value: Quaternion, expected: Array, label: String, tolerance: float = .000001) -> void:
	var values := [value.x, value.y, value.z, value.w]
	for index in range(4):
		if expected[index] is String:
			h._check(is_nan(values[index]) if expected[index] == "NaN" else values[index] == INF if expected[index] == "Infinity" else values[index] == -INF, label)
		else:
			h._check(absf(float(values[index]) - float(expected[index])) <= maxf(tolerance, absf(float(expected[index])) * tolerance), label)

static func frame(matrix: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(matrix[0], matrix[1], matrix[2]), Vector3(matrix[4], matrix[5], matrix[6]), Vector3(matrix[8], matrix[9], matrix[10])),
		Vector3(matrix[12], matrix[13], matrix[14]))
