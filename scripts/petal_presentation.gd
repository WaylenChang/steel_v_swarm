class_name PetalPresentation
extends RefCounted

var profile: Dictionary = {}
var parts: Array = []
var meshes: Dictionary = {}
var motion := PetalMotion.new()
var probe: Callable
var code_at: Callable
var time := 0.0

func configure(root: Node3D, source: Dictionary, season: String, low: bool, height: Callable, ground_code: Callable) -> bool:
	profile = {}
	parts.clear()
	meshes.clear()
	time = 0
	probe = height
	code_at = ground_code
	for variant: Dictionary in source.variants:
		if variant.season == season and bool(variant.low) == low:
			profile = variant
	if profile.is_empty():
		push_error("Missing original petal season/power-mode capture")
		return false
	motion.rules = profile.constants
	time = float(profile.time)
	parts = profile.parts.duplicate(true)
	for node: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		if node.has_meta("source_petal_mesh"):
			node.visible = false
			meshes[int(node.get_meta("source_petal_mesh"))] = node
	for batch: Dictionary in profile.batches:
		var node: MultiMeshInstance3D = meshes.get(int(batch.id))
		if node == null or node.multimesh == null or node.multimesh.instance_count != int(batch.count) or node.multimesh.mesh.get_surface_count() != 1:
			push_error("Missing original petal tone MultiMesh")
			return false
		node.multimesh = node.multimesh.duplicate()
		var material: Material = node.material_override if node.material_override != null else node.multimesh.mesh.surface_get_material(0)
		if material == null:
			push_error("Missing original petal tone material")
			return false
		node.material_override = material.duplicate()
		node.material_override.render_priority = int(batch.priority)
		node.visible = true
		RenderingServer.instance_set_ignore_culling(node.get_instance(), true)
	return true

func advance(delta: float, dynamics: Dictionary) -> void:
	if parts.is_empty():
		return
	var step := 0.0 if is_nan(delta) else clampf(delta, 0, float(motion.rules.DT_MAX))
	time += step
	for part: Dictionary in parts:
		motion.advance(part, step, time, dynamics)
		if float(part.get("groundTime", 0)) > 0 and not ControlPreferences.truthy(part.get("wasGrounded")):
			part.restY = probe.call(float(part.cx) + float(part.ox), float(part.cz) + float(part.oz))
			part.restDry = int(code_at.call(float(part.cx) + float(part.ox), float(part.cz) + float(part.oz))) == 0
		part.wasGrounded = float(part.get("groundTime", 0)) > 0
		var resting := bool(part.wasGrounded) or ControlPreferences.truthy(part.get("lifted"))
		var base: Variant = part.get("restY") if resting else part.y0
		var visible := BodyMotionState._finite(base) and (not resting or bool(part.get("restDry", false)))
		var position := Vector3(float(part.cx) + float(part.ox), float(base) + float(part.oy) if visible else 0, float(part.cz) + float(part.oz))
		var rotation := SourceQuaternion.axis_angle(Vector3(part.ax, part.ay, part.az), part.ang)
		if float(part.get("groundTime", 0)) > 0:
			rotation = WeaponPresentation.source_rotation({"rotation": [-PI / 2, 0, part.a], "order": "XYZ"})
		var fade: Variant = part.get("fade")
		var size := float(part.sz) * (1.0 if fade == null else float(fade)) if visible else 0.0
		var transform := Transform3D(SourceQuaternion.basis(rotation).scaled_local(Vector3(size * float(motion.rules.ASPECT), size, size)), position)
		for batch: Dictionary in profile.batches:
			if int(batch.tone) == int(part.tone):
				meshes[int(batch.id)].multimesh.set_instance_transform(int(part.mi), transform)
				break
