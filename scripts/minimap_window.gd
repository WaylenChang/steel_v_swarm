class_name MinimapWindow
extends RefCounted

static func available() -> bool:
	var rules: Dictionary = Content.balance.get("minimap", {})
	return rules.has("markers") and rules.has("cadence") and rules.has("labels") and rules.has("canvas") and rules.has("lanes") and rules.has("context") and rules.has("fog")

static func label(near: bool, width: float) -> String:
	var labels: Dictionary = Content.balance.minimap.labels
	if not near:
		return String(labels.full)
	var whole := floorf(width)
	var rounded := whole + 1 if width - whole >= .5 else whole
	return labels.near % int(rounded)

static func bounds(terrain: Dictionary, near: bool, position: Vector2, kind: String) -> Rect2:
	return rectangle(components(terrain, near, position, kind))

static func components(terrain: Dictionary, near: bool, position: Vector2, kind: String) -> Dictionary:
	var min_x := float(terrain.minX)
	var max_x := float(terrain.maxX)
	var min_z := float(terrain.minZ)
	var max_z := float(terrain.maxZ)
	if not near:
		return {"x0": min_x, "z0": min_z, "x1": max_x, "z1": max_z}
	var rules: Dictionary = Content.balance.minimap
	var sight := float(Content.constants.UNITS.get(kind, {}).get("sight", 0))
	if sight == 0:
		sight = float(rules.SPEC_R)
	var radius := maxf(float(rules.MIN_R), sight * float(Content.constants.GAME.AIM_SIGHT_MULT) * float(rules.PAD))
	var half_x := minf(radius, (max_x - min_x) / 2)
	var half_z := minf(radius, (max_z - min_z) / 2)
	var center_x := maxf(min_x + half_x, minf(max_x - half_x, float(position.x)))
	var center_z := maxf(min_z + half_z, minf(max_z - half_z, float(position.y)))
	var left := center_x - half_x
	var top := center_z - half_z
	return {"x0": left, "z0": top, "x1": center_x + half_x, "z1": center_z + half_z}

static func rectangle(window: Dictionary) -> Rect2:
	return Rect2(Vector2(window.x0, window.z0), Vector2(float(window.x1) - float(window.x0), float(window.z1) - float(window.z0)))

static func project(point: Vector2, window: Rect2, canvas: Vector2) -> Vector2:
	return Vector2((float(point.x) - float(window.position.x)) / float(window.size.x) * float(canvas.x),
		(float(point.y) - float(window.position.y)) / float(window.size.y) * float(canvas.y))

static func project_components(x: float, z: float, window: Dictionary, canvas: Vector2) -> Vector2:
	return Vector2(_project_axis(x, float(window.x0), float(window.x1), float(canvas.x)),
		_project_axis(z, float(window.z0), float(window.z1), float(canvas.y)))

static func project_components_pair(x: float, z: float, window: Dictionary, canvas: Vector2) -> Array:
	return [_project_axis(x, float(window.x0), float(window.x1), float(canvas.x)),
		_project_axis(z, float(window.z0), float(window.z1), float(canvas.y))]

static func _project_axis(value: float, start: float, end: float, extent: float) -> float:
	return (value - start) / (end - start) * extent

static func texture_region(terrain: Dictionary, window: Rect2, image_size: Vector2, precise: Dictionary = {}) -> Rect2:
	if not precise.is_empty():
		var min_x := float(terrain.minX)
		var min_z := float(terrain.minZ)
		var width := float(terrain.maxX) - min_x
		var height := float(terrain.maxZ) - min_z
		var x0 := (float(precise.x0) - min_x) / width * float(image_size.x)
		var z0 := (float(precise.z0) - min_z) / height * float(image_size.y)
		var x1 := (float(precise.x1) - min_x) / width * float(image_size.x)
		var z1 := (float(precise.z1) - min_z) / height * float(image_size.y)
		return Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0))
	var full := bounds(terrain, false, Vector2.ZERO, "")
	return Rect2(project(window.position, full, image_size), window.size / full.size * image_size)
