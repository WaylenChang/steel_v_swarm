class_name BloodSplatOverlay
extends Control

var state := BloodSplatState.new()
var paint := {"blood": SplatPaintState.new(), "glint": SplatPaintState.new()}
var layers: Dictionary = {}
var tiles := {"blood": {}, "glint": {}}
var free_tiles: Array[SplatTile] = []
var last_serial := -1
var binding: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for kind: String in ["blood", "glint"]:
		var layer := Control.new()
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		layers[kind] = layer
	resized.connect(_resize_tiles)

func observe(pilot: BattleUnit) -> void:
	var next: Array = [pilot.entity_id, pilot.view_reset, pilot.alive()] if pilot != null else []
	if binding != next:
		clear()
		binding = next

func receive(event: Dictionary, pilot: BattleUnit) -> bool:
	if pilot == null or pilot.camera == null or int(event.get("peer", 0)) != pilot.peer_id:
		return false
	observe(pilot)
	var serial := int(event.blood_serial)
	if serial <= last_serial:
		return false
	last_serial = serial
	var camera := pilot.camera
	var area := camera.get_viewport().get_visible_rect().size
	return state.spray(event, camera.global_transform, camera.fov, area.x / area.y if area.y > 0 else 1.0,
		{"side": pilot.side, "dead": not pilot.alive(), "max_hp": pilot.max_hp, "max_shield": pilot.max_shield,
			"defending": pilot.defending, "shield": pilot.shield})

func advance(delta: float) -> void:
	var updates := state.advance(delta)
	for kind: String in ["blood", "glint"]:
		if updates[kind] != null:
			sync_layer(kind, updates[kind])

func sync_layer(kind: String, entries: Array) -> void:
	var changes: Dictionary = paint[kind].sync(entries)
	for id: int in changes.removed:
		var tile: SplatTile = tiles[kind][id]
		tile.retire()
		tiles[kind].erase(id)
		var maximum := int(Content.balance.screenSplats.blood.MAX) + int(Content.balance.screenSplats.glint.MAX)
		if free_tiles.size() < maximum:
			free_tiles.append(tile)
		else:
			tile.queue_free()
	for entry: Dictionary in changes.added:
		var tile: SplatTile
		if free_tiles.is_empty():
			tile = SplatTile.new()
			layers[kind].add_child(tile)
		else:
			tile = free_tiles.pop_back()
			if tile.get_parent() != layers[kind]:
				tile.reparent(layers[kind], false)
		layers[kind].move_child(tile, layers[kind].get_child_count() - 1)
		tile.configure(entry, kind, size)
		tiles[kind][int(entry.id)] = tile
	for id: int in paint[kind].live:
		tiles[kind][id].set_opacity(float(paint[kind].live[id].opacity))

func _resize_tiles() -> void:
	for kind: String in ["blood", "glint"]:
		for tile: SplatTile in tiles[kind].values():
			tile.resize_canvas(size)

func clear() -> void:
	var updates := state.clear()
	if layers.is_empty():
		return
	sync_layer("blood", updates.blood)
	sync_layer("glint", updates.glint)

func reset_room() -> void:
	clear()
	last_serial = -1
	binding = []
