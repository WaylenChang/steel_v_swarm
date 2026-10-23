class_name GeometryLodState
extends RefCounted

var trim: Variant = null
var outline: Variant = null

func observe(frame: int, source_id: String, distance_squared: float, aim_blend: float, rules: Dictionary) -> Dictionary:
	var signed_frame := frame & 0xffffffff
	if signed_frame >= 0x80000000:
		signed_frame -= 0x100000000
	if trim != null and not BodyPresentation.update_due(signed_frame, source_id, int(rules.STRIDE)):
		return {}
	var next_trim := keep(distance_squared, far_distance(float(rules.TRIM_M), aim_blend, rules), trim, rules)
	var next_outline := keep(distance_squared, far_distance(float(rules.OUTLINE_M), aim_blend, rules), outline, rules)
	if next_trim == trim and next_outline == outline:
		return {}
	trim = next_trim
	outline = next_outline
	return {"trim": trim, "outline": outline}

static func far_distance(base: float, aim_blend: float, rules: Dictionary) -> float:
	var blend := 0.0 if is_nan(aim_blend) else clampf(aim_blend, 0, 1)
	return maxf(0, base) * (1 + float(rules.ZOOM_F) * blend)

static func keep(distance_squared: float, far: float, previous: Variant, rules: Dictionary) -> bool:
	var bound := far if previous == null or previous else far * float(rules.HYST)
	return distance_squared <= bound * bound

static func apply(root: Node, trim_high: bool, outline_high: bool) -> int:
	var changed := 0
	if root is Node3D and not root.get_meta("geoKeep", false):
		var wanted: Variant = outline_high if root.get_meta("isOutline", false) else trim_high if root.get_meta("geoDetail", false) else null
		if wanted != null and root.visible != wanted:
			root.visible = wanted
			changed += 1
	# Source traverse visits children even when a parent's geoKeep opts out.
	for child: Node in root.get_children():
		changed += apply(child, trim_high, outline_high)
	return changed
