extends Control

var state: Dictionary = {}
var map_data: Dictionary = {}
var side := "STEEL"
var missile_points: Array = []
var near := false
var focus := Vector2.ZERO
var hero_kind := ""
var window := Rect2()
var canvas: Control
var markers := MinimapMarkerState.new()
var positions: Dictionary = {}
var own_id := 0
var heading := 0.0
var cadence := MinimapCadence.new()
var draw_enabled := false
var mode_font: SystemFont
var base_texture: Texture2D
var base_canvas: Control
var lane_view: MinimapLanes
var vision := MinimapVision.new()
var fog_view: MinimapFog
var view_peer := 0
var view_dead := true
var aiming := false
var weather_fog := 0.0

func _ready() -> void:
	base_canvas = Control.new()
	base_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(base_canvas)
	base_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_canvas.draw.connect(_draw_base)
	fog_view = MinimapFog.new()
	base_canvas.add_child(fog_view)
	lane_view = MinimapLanes.new()
	base_canvas.add_child(lane_view)
	lane_view.hide()
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_map)

func configure(map: Dictionary, allegiance: String, base: Texture2D = null) -> void:
	clear()
	map_data = map
	base_texture = base
	side = allegiance
	if MinimapWindow.available():
		var dimensions: Array = Content.balance.minimap.canvas
		size = Vector2(dimensions[0], dimensions[1])
		cadence.configure(float(Time.get_ticks_msec()) / 1000.0)
		if not Session.dedicated:
			fog_view.configure(size)
	clip_contents = true
	queue_redraw()

func clear() -> void:
	map_data = {}
	base_texture = null
	side = ""
	near = false
	focus = Vector2.ZERO
	hero_kind = ""
	state = {}
	missile_points.clear()
	markers.bunkers.clear()
	vision.clear()
	positions.clear()
	own_id = 0
	heading = 0
	view_peer = 0
	view_dead = true
	aiming = false
	weather_fog = 0
	draw_enabled = false
	cadence.invalidate()
	if fog_view != null:
		fog_view.clear()
	if lane_view != null:
		lane_view.clear()
		lane_view.hide()
	queue_redraw()
	if canvas != null:
		canvas.queue_redraw()
		base_canvas.queue_redraw()

func toggle_mode() -> String:
	near = not near
	cadence.invalidate()
	return Content.balance.minimap.notices["near" if near else "full"]

func advance(now: float) -> bool:
	if map_data.is_empty() or not MinimapWindow.available() or not cadence.advance(now):
		return false
	draw_enabled = true
	window = MinimapWindow.bounds(map_data.bounds, near, focus, hero_kind)
	lane_view.update_window(window, size)
	lane_view.show()
	base_canvas.queue_redraw()
	canvas.queue_redraw()
	return true

func update_fog(now: float, columns: Array, shared_blockers: SourceBlockerQuery = null) -> void:
	var rows: Array = []
	if not side.is_empty():
		for unit: Dictionary in state.get("units", []):
			var point: Vector3 = positions.get(int(unit.id), unit.position)
			rows.append({"kind": unit.kind, "side": unit.side, "hero": not String(unit.character).is_empty(),
				"self": int(unit.id) == own_id, "peer": unit.peer, "hp": unit.hp, "dead": bool(unit.get("dead", float(unit.hp) <= 0)),
				"decoy": unit.kind == "decoy", "lost": unit.get("special", {}).get("lost", false),
				"point": Vector2(point.x, point.z)})
	var view := {"side": side, "peer": view_peer, "kind": hero_kind, "dead": view_dead,
		"aiming": aiming, "fog": weather_fog, "point": focus}
	fog_view.update_view(MinimapVision.sources(rows, view) if not side.is_empty() else [],
		map_data.bounds, window, side, now < vision.pulse_until, columns, shared_blockers)

func accept_snapshot(snapshot: Dictionary) -> void:
	state = snapshot
	side = snapshot.get("vision_side", side)
	markers.remember(snapshot.get("units", []))
	for event: Dictionary in snapshot.get("events", []):
		vision.observe(event, side, float(Time.get_ticks_msec()) / 1000.0)

func _draw() -> void:
	if map_data.is_empty() or not MinimapWindow.available():
		return
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))

func _draw_base() -> void:
	if not draw_enabled or map_data.is_empty() or not MinimapWindow.available():
		return
	window = MinimapWindow.bounds(map_data.bounds, near, focus, hero_kind)
	if base_texture != null:
		base_canvas.draw_texture_rect_region(base_texture, Rect2(Vector2.ZERO, size),
			MinimapWindow.texture_region(map_data.bounds, window, base_texture.get_size()))

func _draw_map() -> void:
	if not draw_enabled or map_data.is_empty() or not MinimapWindow.available():
		return
	window = MinimapWindow.bounds(map_data.bounds, near, focus, hero_kind)
	var own: Variant = MinimapWindow.project(focus, window, size) if not side.is_empty() else null
	var commands := marker_commands()
	# Source missiles precede the own-view arrow and follow the retained bunkers.
	var arrow: Dictionary = commands.pop_back() if own != null else {}
	for command: Dictionary in commands:
		_draw_marker(command)
	if not missile_points.is_empty():
		var marker: Dictionary = Content.balance.missile.presentation.minimap
		var extent := Vector2(marker.size[0], marker.size[1])
		var color := Color.hex((int(marker.color) << 8) | 0xff)
		for point: Vector3 in missile_points:
			canvas.draw_rect(Rect2(_project(point) - extent * .5, extent), color)
	if not arrow.is_empty():
		_draw_marker(arrow)
	canvas.draw_set_transform(Vector2.ZERO)
	_draw_label()

func _draw_label() -> void:
	var rules: Dictionary = Content.balance.minimap.labels
	if mode_font == null:
		mode_font = SystemFont.new()
		mode_font.font_names = PackedStringArray([String(rules.fontFamily)])
	var font_size := int(rules.fontSize)
	var text := MinimapWindow.label(near, window.size.x)
	var measured := mode_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box: Array = rules.box.rect
	var background: Array = rules.box.colour
	canvas.draw_rect(Rect2(box[0], size.y + float(box[1]), measured.x + float(box[2]), box[3]),
		Color(background[0], background[1], background[2], background[3]))
	var colour: Array = rules.colours["near" if near else "full"]
	canvas.draw_string(mode_font, Vector2(rules.position[0], size.y + float(rules.position[1]) - mode_font.get_descent(font_size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(colour[0], colour[1], colour[2], colour[3]))

func marker_commands() -> Array:
	window = MinimapWindow.bounds(map_data.bounds, near, focus, hero_kind)
	var rows: Array = []
	for unit: Dictionary in state.get("units", []):
		rows.append({"kind": unit.kind, "side": unit.side, "hero": not String(unit.character).is_empty(),
			"self": int(unit.id) == own_id, "neutral": unit.get("special", {}).get("neutral", false),
			"point": _project(positions.get(int(unit.id), unit.position))})
	var known: Array = []
	for record: Dictionary in markers.bunkers.values():
		known.append({"side": record.side, "point": MinimapWindow.project(record.point, window, size)})
	var own: Variant = MinimapWindow.project(focus, window, size) if not side.is_empty() else null
	return MinimapMarkerState.commands(rows, side, known, own, heading)

func _draw_marker(command: Dictionary) -> void:
	canvas.draw_set_transform(Vector2(command.position[0], command.position[1]), float(command.rotation))
	var colour := Color(command.colour[0], command.colour[1], command.colour[2], command.colour[3])
	var width := float(command.width) if command.width != null else -1.0
	match command.shape:
		"rect":
			canvas.draw_rect(Rect2(command.rect[0], command.rect[1], command.rect[2], command.rect[3]), colour, command.fill, width, true)
		"circle":
			canvas.draw_circle(Vector2(command.center[0], command.center[1]), float(command.radius), colour, command.fill, width, true)
		"polygon":
			var points := PackedVector2Array()
			for point: Array in command.points:
				points.append(Vector2(point[0], point[1]))
			canvas.draw_colored_polygon(points, colour)

func _project(point: Vector3) -> Vector2:
	return MinimapWindow.project(Vector2(point.x, point.z), window, size)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.08, 0.9)
	style.border_color = Color("477482")
	style.set_border_width_all(1)
	return style

