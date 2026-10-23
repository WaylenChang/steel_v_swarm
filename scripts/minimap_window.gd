class_name MinimapWindow
extends RefCounted

static func available() -> bool:
	var rules: Dictionary = Content.balance.get("minimap", {})
	return rules.has("markers") and rules.has("cadence") and rules.has("labels") and rules.has("canvas") and rules.has("lanes") and rules.has("context") and rules.has("fog")

static func label(near: bool, width: float) -> String:
	var labels: Dictionary = Content.balance.minimap.labels
	return labels.near % int(floorf(width + .5)) if near else String(labels.full)

static func bounds(terrain: Dictionary, near: bool, position: Vector2, kind: String) -> Rect2:
	var full := Rect2(Vector2(terrain.minX, terrain.minZ), Vector2(terrain.maxX - terrain.minX, terrain.maxZ - terrain.minZ))
	if not near:
		return full
	var rules: Dictionary = Content.balance.minimap
	var sight := float(Content.constants.UNITS.get(kind, {}).get("sight", 0))
	if sight == 0:
		sight = float(rules.SPEC_R)
	var radius := maxf(float(rules.MIN_R), sight * float(Content.constants.GAME.AIM_SIGHT_MULT) * float(rules.PAD))
	var half := Vector2(minf(radius, full.size.x / 2), minf(radius, full.size.y / 2))
	var center := position.clamp(full.position + half, full.end - half)
	return Rect2(center - half, half * 2)

static func project(point: Vector2, window: Rect2, canvas: Vector2) -> Vector2:
	return (point - window.position) / window.size * canvas

static func texture_region(terrain: Dictionary, window: Rect2, image_size: Vector2) -> Rect2:
	var full := bounds(terrain, false, Vector2.ZERO, "")
	return Rect2(project(window.position, full, image_size), window.size / full.size * image_size)
