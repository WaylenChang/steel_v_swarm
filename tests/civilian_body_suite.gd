extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("civilianBodyGeometry"):
		h._check(false, "Regenerate original per-ID civilian geometry and articulated-frame references")
		return
	for item: Dictionary in fixtures.civilianBodyGeometry:
		var unit := BattleUnit.new()
		h.add_child(unit)
		unit.configure({"id": int(item.seed), "kind": "civilian", "side": "", "position": Vector3.ZERO,
			"special": {"role": "civilian", "civil_side": item.side, "profession": int(item.profession)}})
		if unit.body_presentation == null:
			h._check(false, "Pack original civilian components")
			unit.free()
			continue
		unit.body.rotation.y = 0
		unit.body_presentation.pending_snap = false
		Helper.compare(h, unit.body.profile.appearance, item.appearance, "Original civilian seed/profession appearance is independent of combat RNG")
		Helper.compare(h, unit.geometry_override, item.dimensions, "Original per-ID civilian silhouette and asymmetric model centre")
		var previous := Vector3.ZERO
		var previous_yaw := 0.0
		for step: Dictionary in item.steps:
			var point := BodyPose.vector(step.position)
			unit.body.poses.set_position(unit.body.source_root, point)
			unit.body.poses.set_axis(unit.body.source_root, "y", step.yaw)
			unit.body.step_combat(unit.body_presentation.entity, step.now, step.delta)
			unit.body.step_locomotion(unit.body_presentation.entity, step.delta, step.now, previous, previous_yaw)
			_compare_meshes(h, unit.body, step.meshes)
			previous = point
			previous_yaw = step.yaw
		unit.free()

static func _compare_meshes(h: Node, body: BodyRig, expected: Array) -> void:
	var meshes: Array = body.source_root.find_children("*", "MeshInstance3D", true, false).filter(func(mesh): return not mesh.get_meta("isOutline", false))
	h._check(meshes.size() == expected.size(), "Original civilian clothing/hair/equipment/ring mesh count")
	for reference: Dictionary in expected:
		var found := -1
		for index in range(meshes.size()):
			var mesh := meshes[index] as MeshInstance3D
			if mesh.get_meta("source_name") != reference.name:
				continue
			var material := mesh.get_active_material(0) as BaseMaterial3D
			if int(material.albedo_color.to_rgba32() >> 8) != int(reference.color):
				continue
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			if vertices.size() != reference.points.size():
				continue
			if not vertices.is_empty() and (mesh.global_transform * vertices[0]).distance_to(BodyPose.vector(reference.points[0])) > .0005:
				continue
			found = index
			for vertex in range(vertices.size()):
				h._check((mesh.global_transform * vertices[vertex]).distance_to(BodyPose.vector(reference.points[vertex])) < .0005,
					"Original per-ID civilian world-space geometry across source body frames")
			var normals: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			var normal_basis := mesh.global_basis.inverse().transposed()
			for vertex in range(mini(normals.size(), reference.normals.size())):
				h._check((normal_basis * normals[vertex]).normalized().distance_to(BodyPose.vector(reference.normals[vertex])) < .001,
					"Original civilian normals retain nonuniform body/shoulder/head scaling")
			break
		h._check(found >= 0, "Original civilian surface and palette binding: " + reference.name)
		if found >= 0:
			meshes.remove_at(found)
