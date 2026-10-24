class_name RoomWorldPrebuild
extends Node

signal progress
signal changed

var resources: RoomWorldResources
var selected: Dictionary = {}
var settings: Dictionary = {}
var generation := 0
var building := false
var failure := ""
var prepared: BattleWorld
var prepared_viewport: SubViewport

static func identity(map: Dictionary, environment: Dictionary, architecture_seed: int) -> Dictionary:
	# A native bundle covers geography. Runtime placement, sides and environment
	# must also match before an instantiated world can be transferred.
	return {"map": map.duplicate(true), "environment": environment.duplicate(true), "architecture_seed": architecture_seed}

func request(value: Dictionary, retry := false) -> int:
	var map := Content.battle_map(value)
	var key := identity(map, value.get("env", {}), int(value.get("architecture_seed", 0)))
	if not selected.is_empty() and selected == key and (not retry or failure.is_empty()):
		return generation
	generation += 1
	var ticket := generation
	_release_prepared()
	selected = key
	settings = value.duplicate(true)
	failure = ""
	resources.request(settings, retry)
	changed.emit()
	if not building:
		_build_selected()
	return ticket

func clear() -> void:
	generation += 1
	selected.clear()
	settings.clear()
	failure = ""
	_release_prepared()
	resources.clear()
	changed.emit()

func take(value: Dictionary, destination: Node) -> BattleWorld:
	var ticket := request(value, true)
	while ticket == generation and prepared == null and failure.is_empty():
		await get_tree().process_frame
	if ticket != generation or prepared == null:
		return null
	if not is_instance_valid(destination) or destination.is_queued_for_deletion() or not destination.is_inside_tree():
		return null
	var world := prepared
	prepared = null
	world.reparent(destination, false)
	world.process_mode = Node.PROCESS_MODE_INHERIT
	_release_prepared()
	selected.clear()
	settings.clear()
	generation += 1
	resources.clear()
	changed.emit()
	return world

func _create_world() -> BattleWorld:
	return BattleWorld.new()

func _build_selected() -> void:
	building = true
	while not selected.is_empty():
		var ticket := generation
		var key := selected.duplicate(true)
		var requested := settings.duplicate(true)
		var data: NativeWorldData = await resources.prepare(requested)
		if ticket != generation:
			continue
		if data == null:
			failure = resources.failure if is_instance_valid(resources) else ""
			if failure.is_empty():
				failure = "Native world resource preparation was interrupted"
			changed.emit()
			if ticket != generation:
				continue
			break
		var viewport := SubViewport.new()
		viewport.size = Vector2i.ONE
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var world := _create_world()
		world.process_mode = Node.PROCESS_MODE_DISABLED
		viewport.add_child(world)
		world.build_progress.connect(func():
			if ticket == generation:
				progress.emit())
		await world.build(key.map, key.environment)
		if ticket != generation:
			viewport.queue_free()
			continue
		if not world.build_complete:
			failure = world.build_error if not world.build_error.is_empty() else "Native room world preparation did not finish"
			viewport.queue_free()
			changed.emit()
			if ticket != generation:
				continue
			break
		world.set_meta("room_prebuild_identity", key)
		prepared = world
		prepared_viewport = viewport
		changed.emit()
		if ticket != generation:
			continue
		progress.emit()
		if ticket != generation:
			continue
		break
	building = false

func _release_prepared() -> void:
	if is_instance_valid(prepared_viewport):
		prepared_viewport.queue_free()
	elif is_instance_valid(prepared):
		prepared.queue_free()
	prepared = null
	prepared_viewport = null
