class_name PipView
extends Control

# Three render layers isolate each source body and the current cockpit per camera.
const COCKPIT_MASK := 1 << 17
const SOURCE_MASKS := [1 << 18, 1 << 19]
const ALL_LAYERS := (1 << 20) - 1

var views: Array[Dictionary] = []
var layers: Dictionary = {}
var pending_tags: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	RenderingServer.frame_pre_draw.connect(_begin_frame)
	RenderingServer.frame_post_draw.connect(_end_frame)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		clear()

func update_view(battle: BattleSimulation, pilot: BattleUnit, side: String, render_scale: float = 1.0) -> void:
	var rules: Dictionary = Content.balance.get("pip", {})
	if rules.is_empty() or battle == null or battle.world == null or pilot == null or not is_visible_in_tree():
		clear()
		return
	var rows: Array = []
	for actor: BattleUnit in battle.units.values():
		var peer := int(actor.special.get("owner_peer", actor.peer_id))
		if peer != pilot.peer_id:
			continue
		rows.append({"id": actor.entity_id, "peer": peer,
			"hero": actor.is_hero(), "self": actor == pilot, "dead": not actor.alive(), "decoy": actor.kind == "decoy",
			"lost": bool(actor.special.get("lost", false)), "index": 0, "unit": actor})
	var selected := PipViewState.sources(rows, pilot.peer_id, pilot.kind == "drone", not pilot.alive(), side, Controls.low_power(), render_scale, rules)
	pending_tags.clear()
	if not selected.is_empty() and _renderable_root(pilot.cockpit):
		pending_tags.append({"root": pilot.cockpit, "mask": COCKPIT_MASK})
	for index in selected.size():
		if index >= views.size():
			_add_view()
		var view: Dictionary = views[index]
		var actor: BattleUnit = selected[index].unit
		if not _renderable_root(actor.model):
			_disable_view(view)
			continue
		pending_tags.append({"root": actor.model, "mask": SOURCE_MASKS[index]})
		var plan := PipViewState.frame(get_viewport_rect().size, index, actor.model.global_position, actor.facing_yaw(), actor.kind == "decoy", rules)
		var rect: Rect2 = plan.rect
		var margin := float(rules.BORDER)
		view.border.position = rect.position - Vector2.ONE * margin
		view.border.size = rect.size + Vector2.ONE * margin * 2
		view.border.color = Color(Content.side_info(side).color)
		view.image.position = Vector2.ONE * margin
		view.image.size = rect.size
		view.viewport.world_3d = battle.get_world_3d()
		view.viewport.size = Vector2i(maxi(1, int(rect.size.x)), maxi(1, int(rect.size.y)))
		view.camera.cull_mask = ALL_LAYERS & ~COCKPIT_MASK & ~SOURCE_MASKS[index]
		view.camera.near = float(rules.NEAR)
		view.camera.far = maxf(float(battle.world.bounds.maxX) - float(battle.world.bounds.minX), float(battle.world.bounds.maxZ) - float(battle.world.bounds.minZ)) * float(rules.FAR_FACTOR)
		view.camera.fov = plan.fov
		var orientation := SourceQuaternion.axis_angle(Vector3.UP, float(plan.yaw))
		view.camera.global_transform = Transform3D(SourceQuaternion.basis(orientation), plan.position)
		view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.border.show()
	for index in range(selected.size(), views.size()):
		_disable_view(views[index])
	_restore_unused({})

func _begin_frame() -> void:
	if is_queued_for_deletion() or not is_visible_in_tree():
		clear()
		return
	var retained := {}
	var valid_tags: Array[Dictionary] = []
	var source_available := false
	for tag: Dictionary in pending_tags:
		if _renderable_root(tag.root):
			_tag(tag.root, tag.mask, retained)
			valid_tags.append(tag)
			source_available = source_available or SOURCE_MASKS.has(tag.mask)
		else:
			var index := SOURCE_MASKS.find(tag.mask)
			if index >= 0 and index < views.size():
				_disable_view(views[index])
	if not source_available:
		valid_tags.clear()
		retained.clear()
	pending_tags = valid_tags
	_restore_unused(retained)

func _renderable_root(root: Variant) -> bool:
	# Cached tags can outlive their node, or an ancestor can be queued first.
	if not is_instance_valid(root) or not root is Node or not root.is_inside_tree():
		return false
	var current: Node = root
	while current != null:
		if current.is_queued_for_deletion():
			return false
		current = current.get_parent()
	return true

func _disable_view(view: Dictionary) -> void:
	view.border.hide()
	view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.viewport.world_3d = null

func _end_frame() -> void:
	# Gameplay copies (retired bodies, effects) must never inherit temporary masks.
	_restore_unused({})

func _add_view() -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.handle_input_locally = false
	add_child(viewport)
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	camera.current = true
	var border := ColorRect.new()
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	border.add_child(image)
	views.append({"viewport": viewport, "camera": camera, "border": border, "image": image})

func _tag(root: Node, mask: int, retained: Dictionary) -> void:
	var nodes: Array[Node] = root.find_children("*", "VisualInstance3D", true, false)
	if root is VisualInstance3D:
		nodes.append(root)
	for node: VisualInstance3D in nodes:
		var id := node.get_instance_id()
		if not layers.has(id):
			layers[id] = {"node": node, "mask": node.layers}
		SourceOutlineBinding.set_layers(node, mask)
		retained[id] = true

func _restore_unused(retained: Dictionary) -> void:
	for id: int in layers.keys():
		if retained.has(id):
			continue
		var record: Dictionary = layers[id]
		if is_instance_valid(record.node):
			SourceOutlineBinding.set_layers(record.node, record.mask)
		layers.erase(id)

func clear() -> void:
	pending_tags.clear()
	for view: Dictionary in views:
		_disable_view(view)
	_restore_unused({})

func _exit_tree() -> void:
	clear()
