class_name BossHud
extends Control

var active_id := 0
var last_seen := 0.0
var active_unit: BattleUnit
var title: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	hide()

func update_view(simulation: BattleSimulation, camera: Camera3D, now: float) -> void:
	if simulation.defending_side.is_empty() or camera == null:
		hide()
		return
	var rules: Dictionary = Content.balance.siege
	var best_id := 0
	var best_distance := INF
	var viewport := camera.get_viewport().get_visible_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return
	for unit: BattleUnit in simulation.units.values():
		if not unit.special.get("boss", false) or not unit.alive() or not unit.visible or unit.side != simulation.defending_side:
			continue
		var point := unit.aim_point()
		if not point.is_finite():
			continue
		var local := camera.global_transform.affine_inverse() * point
		if local.z > -float(rules.near):
			continue
		var screen := camera.unproject_position(point)
		if absf(2 * screen.x / viewport.x - 1) > float(rules.view) or absf(1 - 2 * screen.y / viewport.y) > float(rules.view):
			continue
		var distance := camera.global_position.distance_to(point)
		var obstruction := _obstruction_distance(camera.global_position, point)
		if obstruction < distance - float(rules.cover):
			continue
		if distance < best_distance:
			best_distance = distance
			best_id = unit.entity_id
	if best_id != 0:
		active_id = best_id
		last_seen = now
	active_unit = simulation.units.get(active_id)
	if active_unit != null and (not active_unit.special.get("boss", false) or not active_unit.alive() or now - last_seen > float(rules.linger)):
		active_unit = null
		active_id = 0
	visible = active_unit != null
	if not visible:
		return
	var segment: int = int(active_unit.special.get("boss_segment", 0))
	var hero: Dictionary = Content.heroes[active_unit.character]
	title.text = "%s · %s\n%s" % [hero.name, Content.label("boss_phase") % clampi(segment + 1, 1, Content.constants.BOSS.SEG_W.size()), hero.machine]
	title.size = Vector2(size.x, 48)
	queue_redraw()

func _obstruction_distance(origin: Vector3, point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(origin, point, 1)
	query.hit_back_faces = true
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	return origin.distance_to(hit.position) if not hit.is_empty() else INF

func _draw() -> void:
	if not is_instance_valid(active_unit):
		return
	var segment: int = int(active_unit.special.get("boss_segment", 0))
	var config: Dictionary = Content.constants.BOSS
	var color := Color(config.GLOW[clampi(segment, 0, config.GLOW.size() - 1)])
	var frame := Rect2(4, 50, maxf(0, size.x - 8), 42)
	draw_rect(frame.grow(4), Color(color, 0.35))
	draw_rect(frame, Color("#111417"))
	draw_rect(frame, color, false, 2)
	var health := Rect2(8, 69, maxf(0, size.x - 16), 18)
	var fraction := active_unit.hp / active_unit.max_hp if active_unit.max_hp > 0 else 0.0
	for index in range(config.SEG_W.size() - 1, -1, -1):
		var fill := health
		fill.size.x *= SiegeRules.segment_fraction(fraction, index)
		draw_rect(fill, Color(config.SEG_FILL[index]))
	var shield := Rect2(8, 55, maxf(0, size.x - 16), 8)
	draw_rect(shield, Color("#0a1723"))
	shield.size.x *= clampf(active_unit.shield / active_unit.max_shield, 0, 1) if active_unit.max_shield > 0 else 0.0
	draw_rect(shield, Color("#7fd4ff"))
