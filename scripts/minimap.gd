extends Control

var state: Dictionary = {}
var map_data: Dictionary = {}
var side := "STEEL"
var missile_points: Array = []

func _draw() -> void:
	if map_data.is_empty():
		return
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for lane in map_data.lanes:
		var points := PackedVector2Array()
		for point in lane:
			points.append(_project(Vector3(point[0], 0, point[1])))
		draw_polyline(points, Color("748690"), 2, true)
	for unit in state.get("units", []):
		if unit.hp <= 0 or unit.get("special", {}).get("neutral", false):
			continue
		var color := Color(Content.side_info(unit.side).color)
		var radius := 4.0 if unit.kind in ["base", "tower"] else 2.0
		draw_circle(_project(unit.position), radius, color)
	if not missile_points.is_empty():
		var marker: Dictionary = Content.balance.missile.presentation.minimap
		var extent := Vector2(marker.size[0], marker.size[1])
		var color := Color.hex((int(marker.color) << 8) | 0xff)
		for point: Vector3 in missile_points:
			draw_rect(Rect2(_project(point) - extent * .5, extent), color)

func _project(point: Vector3) -> Vector2:
	var bounds: Dictionary = map_data.bounds
	return Vector2(inverse_lerp(bounds.minX, bounds.maxX, point.x), inverse_lerp(bounds.minZ, bounds.maxZ, point.z)) * (size - Vector2(12, 12)) + Vector2(6, 6)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.08, 0.9)
	style.border_color = Color("477482")
	style.set_border_width_all(1)
	return style

