class_name RoomWorldPrebuild
extends Node

signal progress
signal changed

class Transfer extends RefCounted:
	signal completed(world: BattleWorld)

var resources: RoomWorldResources
var selected: Dictionary = {}
var settings: Dictionary = {}
var generation := 0
var building := false
var failure := ""
var prepared: BattleWorld
var prepared_viewport: SubViewport
var building_viewport: SubViewport
var retiring := false

func _enter_tree() -> void:
	retiring = false

static func identity(map: Dictionary, environment: Dictionary, architecture_seed: int) -> Dictionary:
	# A native bundle covers geography. Runtime placement, sides and environment
	# must also match before an instantiated world can be transferred.
	return {"map": map.duplicate(true), "environment": environment.duplicate(true), "architecture_seed": architecture_seed}

func request(value: Dictionary, retry := false) -> int:
	var map := Content.battle_map(value)
	var key := identity(map, value.get("env", {}), int(value.get("architecture_seed", 0)))
	if _active() and not selected.is_empty() and selected == key and (not retry or failure.is_empty()):
		return generation
	generation += 1
	var ticket := generation
	_stop_build()
	_release_prepared()
	if not _active() or not is_instance_valid(resources) or not resources.is_inside_tree():
		selected.clear()
		settings.clear()
		failure = "Room world prebuild requires an active SceneTree and resource loader"
		return ticket
	selected = key
	settings = value.duplicate(true)
	failure = ""
	resources.request(settings, retry)
	if not is_instance_valid(self) or not _active() or ticket != generation:
		return ticket
	changed.emit()
	if is_instance_valid(self) and _active() and ticket == generation:
		building = true
		_build_selected(weakref(self), ticket)
	return ticket

func clear() -> void:
	generation += 1
	selected.clear()
	settings.clear()
	failure = ""
	_stop_build()
	_release_prepared()
	if is_instance_valid(resources):
		resources.clear()
	changed.emit()

func take(value: Dictionary, destination: Node) -> Variant:
	var ticket := request(value, true)
	if not is_instance_valid(self) or not _active() or ticket != generation or not failure.is_empty():
		return null
	if not is_instance_valid(destination) or destination.is_queued_for_deletion() or not destination.is_inside_tree():
		return null
	if prepared != null:
		return _transfer(ticket, destination)
	var transfer := Transfer.new()
	_wait_take(weakref(self), weakref(destination), get_tree(), ticket, transfer)
	return transfer.completed

static func _wait_take(reference: WeakRef, destination: WeakRef, tree: SceneTree, ticket: int, transfer: Transfer) -> void:
	await tree.process_frame
	while true:
		var cache := _current(reference, ticket)
		var target := destination.get_ref() as Node
		if cache == null or target == null or not target.is_inside_tree() or target.is_queued_for_deletion():
			transfer.completed.emit(null)
			return
		if not cache.failure.is_empty():
			transfer.completed.emit(null)
			return
		if cache.prepared != null:
			var world := cache._transfer(ticket, target)
			cache = null
			transfer.completed.emit(world)
			return
		cache = null
		target = null
		await tree.process_frame

func _transfer(ticket: int, destination: Node) -> BattleWorld:
	if not _active() or ticket != generation or not is_instance_valid(prepared) or prepared.is_queued_for_deletion():
		return null
	if not is_instance_valid(destination) or not destination.is_inside_tree() or destination.is_queued_for_deletion():
		return null
	var world := prepared
	var viewport := prepared_viewport
	var previous_selection := selected.duplicate(true)
	var previous_settings := settings.duplicate(true)
	prepared = null
	prepared_viewport = null
	selected.clear()
	settings.clear()
	generation += 1
	var consumed := generation
	if is_instance_valid(resources):
		resources.clear()
	# Seal ownership before reparenting: destination callbacks may replace or free us.
	world.reparent(destination, false)
	var accepted := is_instance_valid(world) and not world.is_queued_for_deletion() and is_instance_valid(destination) \
		and destination.is_inside_tree() and not destination.is_queued_for_deletion() and world.get_parent() == destination
	if not accepted:
		var recoverable := is_instance_valid(world) and not world.is_queued_for_deletion() and is_instance_valid(destination) \
			and world.get_parent() == destination
		if recoverable and is_instance_valid(self) and _active() and generation == consumed \
				and is_instance_valid(viewport) and not viewport.is_queued_for_deletion():
			# Publish rollback ownership before native callbacks; a newer request may replace it.
			prepared = world
			prepared_viewport = viewport
			selected = previous_selection
			settings = previous_settings
			world.reparent(viewport, false)
			if is_instance_valid(self) and _active() and generation == consumed:
				changed.emit()
		else:
			if recoverable:
				world.queue_free()
			if is_instance_valid(viewport):
				viewport.queue_free()
		return null
	if is_instance_valid(viewport):
		viewport.queue_free()
	if is_instance_valid(world) and not world.is_queued_for_deletion():
		world.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(self) and _active() and generation == consumed:
		changed.emit()
	return world if is_instance_valid(world) and not world.is_queued_for_deletion() and is_instance_valid(destination) and world.get_parent() == destination else null

func _create_world() -> BattleWorld:
	return BattleWorld.new()

static func _build_selected(reference: WeakRef, ticket: int) -> void:
	var cache := _current(reference, ticket)
	if cache == null:
		return
	var key := cache.selected.duplicate(true)
	var requested := cache.settings.duplicate(true)
	var loader := cache.resources
	cache = null
	var data: NativeWorldData = await loader.prepare(requested)
	cache = _current(reference, ticket)
	if cache == null:
		return
	if data == null:
		var reason := cache.resources.failure if is_instance_valid(cache.resources) else ""
		cache._fail(reason if not reason.is_empty() else "Native world resource preparation was interrupted")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i.ONE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	cache.building_viewport = viewport
	cache.add_child(viewport)
	cache = _current(reference, ticket)
	if cache == null:
		return
	var world := cache._create_world()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(world)
	cache = _current(reference, ticket)
	if cache == null:
		return
	world.build_progress.connect(cache._forward_progress.bind(ticket))
	cache = null
	await world.build(key.map, key.environment)
	cache = _current(reference, ticket)
	if cache == null:
		return
	if not is_instance_valid(world) or not world.build_complete:
		var reason := world.build_error if is_instance_valid(world) else ""
		cache._fail(reason if not reason.is_empty() else "Native room world preparation did not finish")
		return
	world.set_meta("room_prebuild_identity", key)
	cache.prepared = world
	cache.prepared_viewport = viewport
	cache.building_viewport = null
	cache.building = false
	cache.changed.emit()
	cache = _current(reference, ticket)
	if cache != null:
		cache.progress.emit()

func _active() -> bool:
	return is_inside_tree() and not retiring and not is_queued_for_deletion()

static func _current(reference: WeakRef, ticket: int) -> RoomWorldPrebuild:
	var cache := reference.get_ref() as RoomWorldPrebuild
	return cache if cache != null and cache._active() and cache.generation == ticket else null

func _forward_progress(ticket: int) -> void:
	if _active() and ticket == generation:
		progress.emit()

func _fail(reason: String) -> void:
	_stop_build()
	failure = reason
	changed.emit()

func _stop_build() -> void:
	building = false
	if is_instance_valid(building_viewport):
		building_viewport.queue_free()
	building_viewport = null

func _release_prepared() -> void:
	if is_instance_valid(prepared_viewport):
		prepared_viewport.queue_free()
	elif is_instance_valid(prepared):
		prepared.queue_free()
	prepared = null
	prepared_viewport = null

func _exit_tree() -> void:
	retiring = true
	clear()
