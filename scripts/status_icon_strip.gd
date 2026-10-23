class_name StatusIconStrip
extends HFlowContainer

var durations: Dictionary = {}
var textures: Dictionary = {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)

func clear() -> void:
	durations.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	hide()

func sync(items: Array) -> void:
	if items.is_empty():
		clear()
		return
	var definitions: Dictionary = Content.balance.controls.get("statusIcons", {}).get("definitions", {})
	var active := {}
	for item: Dictionary in items:
		active[item.id] = true
	for id: String in durations.keys():
		if not active.has(id):
			durations.erase(id)
	var viewport := get_viewport_rect().size
	var diameter := maxf(viewport.y * .029, minf(minf(viewport.x, viewport.y) * .04, viewport.x * .029))
	var index := 0
	for item: Dictionary in items:
		if not definitions.has(item.id):
			continue
		if not textures.has(item.id):
			var path := "res://assets/ui/status-%s.svg" % item.id
			if not ResourceLoader.exists(path):
				push_error("Missing original status SVG import: " + path)
				continue
			textures[item.id] = load(path)
		var icon: StatusIcon
		if index < get_child_count():
			icon = get_child(index) as StatusIcon
		else:
			icon = StatusIcon.new()
			add_child(icon)
		icon.sync(item, definitions[item.id], textures[item.id], presentation(item), diameter)
		index += 1
	while get_child_count() > index:
		var child := get_child(get_child_count() - 1)
		remove_child(child)
		child.queue_free()
	visible = index > 0

func presentation(item: Dictionary) -> Dictionary:
	var remaining := float(item.remS)
	var maximum := float(item.get("maxS", 0))
	if maximum == 0:
		maximum = float(durations.get(item.id, remaining))
	if remaining > maximum:
		maximum = remaining
		durations[item.id] = maximum
	elif not durations.has(item.id):
		durations[item.id] = maximum
	var fraction := clampf((maximum - remaining) / maximum, 0, 1) if maximum > 0 else 0.0
	var angle := fraction * PI * 2.0
	return {"timer": "%.1f" % CssDecimal.fixed(remaining, 1) if remaining < 10 else str(floori(remaining + .5)),
		"fraction": fraction, "degrees": CssDecimal.fixed(fraction * 360, 1),
		"dashOffset": CssDecimal.fixed(76.65 * (1 - fraction), 2),
		"tipX": CssDecimal.fixed(14 + 12.2 * sin(angle), 2), "tipY": CssDecimal.fixed(14 - 12.2 * cos(angle), 2),
		"showTip": fraction > .02 and fraction < .98}
