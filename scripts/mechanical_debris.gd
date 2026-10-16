class_name MechanicalDebris
extends Node3D

var batches: Array[MultiMeshInstance3D] = []
var chunks: Array[Dictionary] = []
var elapsed := 0.0
var floor_y := 0.0

func configure(point: Vector3, big: bool, accent: Variant, low_power: bool, sample: Callable) -> void:
	if batches.is_empty():
		var material: BaseMaterial3D
		for index in range(Content.balance.destruction.palette.size()):
			var original := (load("res://assets/npc_effects/chunk%d.scn" % index) as PackedScene).instantiate() as MeshInstance3D
			if material == null:
				material = (original.get_active_material(0) as BaseMaterial3D).duplicate()
				material.vertex_color_use_as_albedo = true
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = MultiMesh.new()
			batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			batch.multimesh.use_colors = true
			batch.multimesh.mesh = original.mesh
			batch.material_override = material
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(batch)
			batches.append(batch)
			original.free()
	var count := (8 if low_power else 14) if big else (4 if low_power else 7)
	var batch_count := 2 if low_power else batches.size()
	for index in range(batches.size()):
		batches[index].visible = index < batch_count
		batches[index].multimesh.instance_count = ceili(float(count - index) / batch_count) if index < batch_count else 0
	chunks.clear()
	elapsed = 0.0
	floor_y = point.y - 2
	for index in range(count):
		var batch := index % batch_count
		var slot := floori(float(index) / batch_count)
		var size := (1.6 if big else .7) * (.6 + float(sample.call()) * .9)
		batches[batch].multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * size), point))
		var color := int(accent) if accent != null and index % 4 == 3 else int(Content.balance.destruction.palette[index % Content.balance.destruction.palette.size()])
		batches[batch].multimesh.set_instance_color(slot, Color.hex((color << 8) | 0xff).srgb_to_linear())
		var angle := float(sample.call()) * TAU
		var up := 6 + float(sample.call()) * (22 if big else 12)
		var out := (14 if big else 8) * (.4 + float(sample.call()))
		var spin := Vector3(float(sample.call()) * 9, float(sample.call()) * 9, float(sample.call()) * 9)
		chunks.append({"batch": batch, "slot": slot, "size": size, "point": point,
			"velocity": Vector3(cos(angle) * out, up, sin(angle) * out), "spin": spin})
	visible = true

func advance(fraction: float, delta: float) -> void:
	elapsed += delta
	for chunk: Dictionary in chunks:
		chunk.velocity.y -= 32 * delta
		chunk.point += chunk.velocity * delta
		if chunk.point.y < floor_y:
			chunk.point.y = floor_y
			chunk.velocity.y *= -.35
			chunk.velocity.x *= .6
			chunk.velocity.z *= .6
		var angles: Vector3 = chunk.spin * elapsed
		var rotation := WeaponPresentation.source_rotation({"rotation": [angles.x, angles.y, angles.z], "order": "XYZ"})
		var size := float(chunk.size) * minf(1, fraction / .3)
		batches[int(chunk.batch)].multimesh.set_instance_transform(int(chunk.slot),
			Transform3D(SourceQuaternion.basis(rotation).scaled_local(Vector3.ONE * size), chunk.point))
