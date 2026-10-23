class_name ClimbPresentation
extends RefCounted

var batches: Dictionary = {}
var routes: Array = []
var age := 0.0

func configure(root: Node3D, accepted: Array) -> bool:
	routes = accepted
	batches.clear()
	age = 0
	var rules: Dictionary = Content.balance.movement.climb.arrows
	for node: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		var key: String = node.get_meta("source_climb_arrow", "")
		if key.is_empty():
			continue
		if key not in ["up", "down"] or batches.has(key) or node.multimesh == null \
				or node.multimesh.instance_count != routes.size() * int(rules.N) * 2:
			push_error("Original climb arrow batches do not match the captured routes")
			return false
		node.multimesh = node.multimesh.duplicate()
		batches[key] = node
	if not routes.is_empty() and batches.size() != 2:
		push_error("Missing original climb arrow geometry")
		return false
	var bounds := AABB()
	var sampled := false
	var margin := float(rules.BAR) + float(rules.W) + float(rules.T)
	for route: Dictionary in routes:
		for band: Array in [[1, float(route.y0) + float(rules.FOOT)], [-1, float(route.y1) + float(rules.HEAD)]]:
			for distance: float in [0.0, float(rules.RUN)]:
				var point := Vector3(float(route.x) + float(route.nx) * float(rules.OUT), float(band[1]) + int(band[0]) * distance,
					float(route.z) + float(route.nz) * float(rules.OUT))
				var box := AABB(point - Vector3.ONE * margin, Vector3.ONE * margin * 2)
				bounds = bounds.merge(box) if sampled else box
				sampled = true
	for batch: MultiMeshInstance3D in batches.values():
		batch.multimesh.custom_aabb = bounds
	advance(0)
	return true

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0:
		return
	age += delta
	var rules: Dictionary = Content.balance.movement.climb.arrows
	var cs := cos(float(rules.SPREAD))
	var sn := sin(float(rules.SPREAD))
	for key: String in batches:
		var batch: MultiMeshInstance3D = batches[key]
		if not is_instance_valid(batch):
			continue
		var direction := 1 if key == "up" else -1
		var index := 0
		for route: Dictionary in routes:
			var tangent := Vector3(-float(route.nz), 0, float(route.nx))
			var normal := Vector3(float(route.nx), 0, float(route.nz))
			var base_y := float(route.y0) + float(rules.FOOT) if direction == 1 else float(route.y1) + float(rules.HEAD)
			for phase in range(int(rules.N)):
				for side: int in [-1, 1]:
					var flow := fposmod(age * float(rules.SPD) + float(phase) / int(rules.N) * float(rules.RUN), float(rules.RUN))
					var edge := minf(1, minf(flow / float(rules.FADE), (float(rules.RUN) - flow) / float(rules.FADE)))
					var scale_factor := float(rules.scaleMinimum) + float(rules.scaleRange) * maxf(0, edge)
					var z_axis := Vector3(-side * tangent.x * sn, direction * cs, -side * tangent.z * sn)
					var x_axis := normal.cross(z_axis)
					var point := Vector3(float(route.x) + normal.x * float(rules.OUT), base_y + direction * flow, float(route.z) + normal.z * float(rules.OUT))
					batch.multimesh.set_instance_transform(index, Transform3D(Basis(x_axis * float(rules.W) * scale_factor,
						normal * float(rules.T), z_axis * float(rules.BAR) * scale_factor), point))
					index += 1
