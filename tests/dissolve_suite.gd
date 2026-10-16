extends RefCounted

class RecordedEffects extends CombatEffects:
	var bursts: Array = []
	func _ready() -> void:
		pass
	func scene_damage_burst(id: int, _kind: String, _point: Vector3, _height: float, _radius: float, stage: int) -> void:
		bursts.append({"id": id, "stage": stage})

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("dissolveMaterials") or not fixtures.has("dissolveGhosts") or not fixtures.has("dissolveClocks") or not DissolveBinding.available():
		h._check(false, "Regenerate source dissolve functions, material bindings and ghost lifecycle fixtures")
		return
	for row: Dictionary in fixtures.dissolveClocks:
		h._near(DissolveBinding.out_at(float(row.time)), float(row.value), "Original clamped dissolve-out clock")
	for row: Dictionary in fixtures.dissolveMaterials:
		_materials(h, row)
	for authority: bool in [false, true]:
		for row: Dictionary in fixtures.dissolveGhosts:
			_ghost(h, row, authority)
	print("DISSOLVE_REFERENCE_PASS ghosts=", fixtures.dissolveGhosts.size())

static func _surface(enabled: bool, color: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.set_meta("source_dissolve", enabled)
	return material

static func _materials(h: Node, row: Dictionary) -> void:
	var root := Node3D.new()
	h.add_child(root)
	root.position = Vector3(12, 20, -9)
	root.rotation = Vector3(.13, .21, -.17)
	root.scale = Vector3(-1.2, 1.7, .9)
	var opaque := _surface(true, Color.hex(0x8090a0ff))
	var plain := _surface(false, Color.hex(0x304050ff))
	plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var transparent := _surface(false, Color.hex(0xb0603059))
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var originals: Array[Material] = [opaque, plain, transparent, opaque if row.shared else opaque.duplicate()]
	var nodes: Array[GeometryInstance3D] = []
	var instance_mesh: Mesh
	for index in range(originals.size()):
		var node: GeometryInstance3D
		if row.instanced and index == 3:
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = MultiMesh.new()
			batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			var box := BoxMesh.new()
			box.material = originals[index]
			instance_mesh = box
			batch.multimesh.mesh = box
			batch.multimesh.instance_count = 2
			batch.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
			batch.multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(8, 4, 2)))
			node = batch
		else:
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			mesh.material_override = originals[index]
			node = mesh
		root.add_child(node)
		node.position = Vector3(index * 2, float(index) / 3, -index)
		nodes.append(node)
	if row.grouped:
		var grouped := MeshInstance3D.new()
		var geometry := ArrayMesh.new()
		var arrays := BoxMesh.new().surface_get_arrays(0)
		for material: Material in [opaque, opaque, plain, transparent, originals[3]]:
			geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			geometry.surface_set_material(geometry.get_surface_count() - 1, material)
		grouped.mesh = geometry
		grouped.set_meta("source_dissolve_slots", [true, true, false, false, true])
		root.add_child(grouped)
	var outline := MeshInstance3D.new()
	outline.mesh = BoxMesh.new()
	outline.material_override = plain
	outline.set_meta("isOutline", true)
	root.add_child(outline)
	var binding := DissolveBinding.new()
	var retained: Array[Material] = []
	for frame: Dictionary in row.steps:
		var anchor: Variant = BodyPose.vector(frame.origin) if frame.origin is Array else null
		h._check(binding.set_progress(root, float(frame.value), anchor) == int(frame.count), "Original material-slot count, including shared bindings")
		h._check(outline.visible == bool(frame.outline), "Original outline shells disappear for all incomplete dissolve values")
		for index in range(nodes.size()):
			var reference: Dictionary = frame.materials[index]
			var material := ViewOcclusion._material(nodes[index], 0)
			if not reference.enabled:
				h._check(material == originals[index], "Transparent and unpatched surfaces remain on their original material")
				continue
			h._check(material is ShaderMaterial and material != originals[index], "Dissolve uniforms stay private to the detached model")
			var shader := material as ShaderMaterial
			h._near(float(shader.get_shader_parameter("source_progress")), float(reference.value), "Original clamped source dissolve uniform")
			h._check((shader.get_shader_parameter("source_origin") as Vector3).distance_to(BodyPose.vector(reference.origin)) < .00001,
				"Dissolve origin changes only when supplied")
			if not retained.is_empty():
				h._check(material == retained[index], "Dissolve writes retain stable material and shader bindings")
		if retained.is_empty():
			for node: GeometryInstance3D in nodes:
				retained.append(ViewOcclusion._material(node, 0))
		h._check((ViewOcclusion._material(nodes[0], 0) == ViewOcclusion._material(nodes[3], 0)) == bool(row.shared),
			"Shared and separately cloned source materials preserve their alias boundary")
	if row.instanced:
		var batch := nodes[3] as MultiMeshInstance3D
		batch.multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(9, 5, 3)))
	binding.release()
	for index in range(nodes.size()):
		h._check(ViewOcclusion._material(nodes[index], 0) == originals[index], "Release restores source material bindings")
	if row.instanced:
		var batch := nodes[3] as MultiMeshInstance3D
		h._check(batch.multimesh.mesh == instance_mesh and batch.multimesh.get_instance_transform(1).origin == Vector3(9, 5, 3),
			"Release restores original geometry while retaining animated instance buffers")
	h._check(opaque.albedo_color == Color.hex(0x8090a0ff) and not opaque.has_meta("source_progress"), "Dissolve cannot mutate imported source materials")
	root.free()

static func _ghost(h: Node, row: Dictionary, authority: bool) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.authoritative = authority
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	var effects := RecordedEffects.new()
	simulation.world.combat_effects = effects
	simulation.world.add_child(effects)
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = 42
	unit.kind = row.kind
	unit.hp = 0
	unit.geometry_override = {"height": 6.0, "radius": 3.0}
	unit.special = {"neutral": row.neutral, "collapsed": row.collapsed}
	if row.kind == "civilian" and not row.neutral:
		unit.special = {"neutral": true, "role": "civilian", "collapsed": row.collapsed}
	unit.model = Node3D.new()
	unit.add_child(unit.model)
	unit.model.position = Vector3(12, 20, -9)
	unit.model.visible = row.visible
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = _surface(row.enabled)
	unit.model.add_child(mesh)
	var outline := MeshInstance3D.new()
	outline.mesh = BoxMesh.new()
	outline.material_override = _surface(false)
	outline.set_meta("isOutline", true)
	unit.model.add_child(outline)
	simulation.victim_reports[42] = {"hp": 100.0}
	var resources := [simulation.rng.state, simulation.projectile_rng.state, simulation.clock, simulation.next_id]
	simulation._retain_removed_body(unit)
	var view: RetiredBody = simulation.retired_bodies[42]
	unit.free()
	var reports := [{"type": "die", "actor": 42}] if row.die else []
	simulation._present_retired_bodies(reports)
	_compare_ghost(h, simulation, effects, view, outline, row.initial)
	for frame: Dictionary in row.frames:
		simulation.step_dissolve_ghosts(float(frame.delta))
		_compare_ghost(h, simulation, effects, view, outline, frame)
	var bursts := effects.bursts.size()
	simulation._present_retired_bodies(reports)
	h._check(effects.bursts.size() == bursts and simulation.dissolve_ghosts.is_empty(), "Repeated death publication cannot renew a dissolve ghost")
	h._check(resources == [simulation.rng.state, simulation.projectile_rng.state, simulation.clock, simulation.next_id],
		"Removed visual ghosts do not advance combat RNG, authority time or identity")
	simulation.free()

static func _compare_ghost(h: Node, simulation: BattleSimulation, effects: RecordedEffects, view: RetiredBody, outline: Node3D, expected: Dictionary) -> void:
	var attached := is_instance_valid(view.model) and not view.model.is_queued_for_deletion()
	h._check(attached == bool(expected.attached) and simulation.dissolve_ghosts.size() == int(expected.ghosts),
		"Original death, visibility, material support and collapsed-neutral removal gates")
	h._check(effects.bursts == expected.bursts, "Only intact neutral removals emit their source destination burst")
	h._check(effects.effects.is_empty(), "Shader dissolve ghosts stay outside the global transient effect budget")
	if not attached:
		return
	h._check(view.model.visible == bool(expected.visible) and outline.visible == bool(expected.outline), "Original ghost and outline visibility")
	h._near(view.age, float(expected.time), "Original ghost clock, including zero-delta updates")
	h._near(view.dissolve.progress, float(expected.value), "Original dissolve-out uniform over ghost lifetime")
	h._check(view.dissolve.origin.distance_to(BodyPose.vector(expected.origin)) < .00001, "Ghost retains its removal-time world anchor")
