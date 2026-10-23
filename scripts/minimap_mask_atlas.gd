class_name MinimapMaskAtlas
extends Node

# Allocation pages limit texture dimensions, never the number of vision sources.
const PAGE_EDGE := 1024

var pages: Array = []
var layouts: Array = []
var previous_sizes := PackedVector2Array()

func clear() -> void:
	for page: Dictionary in pages:
		page.viewport.free()
	pages.clear()
	layouts.clear()
	previous_sizes.clear()

func suspend() -> void:
	for page: Dictionary in pages:
		page.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func update(plans: Array) -> Array:
	var sizes := PackedVector2Array()
	for plan: Dictionary in plans:
		sizes.append(plan.clip.size)
	if sizes != previous_sizes:
		layouts = _pack(sizes)
		previous_sizes = sizes
	var result: Array = []
	for index in layouts.size():
		if index >= pages.size():
			var viewport := SubViewport.new()
			viewport.disable_3d = true
			viewport.transparent_bg = true
			viewport.size = Vector2i(2, 2)
			viewport.world_2d = World2D.new()
			viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(viewport)
			pages.append({"viewport": viewport, "tiles": []})
		var page: Dictionary = pages[index]
		var layout: Dictionary = layouts[index]
		var viewport: SubViewport = page.viewport
		viewport.size = Vector2i(maxi(viewport.size.x, layout.atlas.size.x), maxi(viewport.size.y, layout.atlas.size.y))
		for slot in layout.indices.size():
			if slot >= page.tiles.size():
				var tile := MinimapMaskTile.new()
				viewport.add_child(tile)
				page.tiles.append(tile)
			var tile: MinimapMaskTile = page.tiles[slot]
			var plan: Dictionary = plans[int(layout.indices[slot])]
			tile.configure(plan, layout.atlas.points[slot], viewport.get_texture())
			result.append({"plan": plan, "texture": tile.region})
		for slot in range(layout.indices.size(), page.tiles.size()):
			page.tiles[slot].hide()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for index in range(layouts.size(), pages.size()):
		pages[index].viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return result

static func _pack(sizes: PackedVector2Array) -> Array:
	var result: Array = []
	var batch := PackedVector2Array()
	var indices: Array = []
	var packed := {}
	for index in sizes.size():
		var candidate := batch.duplicate()
		candidate.append(sizes[index])
		var atlas := Geometry2D.make_atlas(candidate)
		if not batch.is_empty() and (atlas.size.x > PAGE_EDGE or atlas.size.y > PAGE_EDGE):
			result.append({"atlas": packed, "indices": indices})
			batch = PackedVector2Array()
			indices = []
			candidate = PackedVector2Array([sizes[index]])
			atlas = Geometry2D.make_atlas(candidate)
		batch = candidate
		indices.append(index)
		packed = atlas
	if not batch.is_empty():
		result.append({"atlas": packed, "indices": indices})
	return result
