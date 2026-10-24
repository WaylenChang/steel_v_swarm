extends Node3D

var assertions := 0
var failures: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		push_error("SEASONAL_PREBUILD_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var selection := WorldVariant.select_required(Array(OS.get_cmdline_user_args()))
	_check(selection.error.is_empty() and selection.worlds.size() == 1, "Select exactly one original seasonal bundle")
	if not failures.is_empty():
		_finish()
		return
	var path: String = selection.worlds.keys()[0]
	var identity: Dictionary = selection.worlds[path]
	var settings := _settings_for(identity)
	_check(not settings.is_empty(), "Selected bundle has its original room/campaign settings")
	if settings.is_empty():
		_finish()
		return
	var loader := RoomWorldResources.new()
	var cache := RoomWorldPrebuild.new()
	cache.resources = loader
	add_child(loader)
	add_child(cache)
	cache.request(settings)
	while cache.building:
		await get_tree().process_frame
	_check(cache.failure.is_empty() and cache.prepared != null, "Complete seasonal world builds in its isolated viewport: " + cache.failure)
	if cache.prepared == null:
		cache.free()
		loader.free()
		_finish()
		return
	var world := cache.prepared
	var data := loader.resource
	_check(data != null and data.resource_path == path, "Prebuilding retains the exact selected seasonal resource")
	_check(world.native_data == data and world.process_mode == Node.PROCESS_MODE_DISABLED,
		"Prepared scenery consumes the retained resource without early processing")
	var renamed := settings.duplicate(true)
	renamed.room_name = "Seasonal preload fixture"
	var ticket := cache.generation
	_check(cache.request(renamed) == ticket and cache.prepared == world, "Name-only edits retain the complete existing seasonal tree")
	var probe: Dictionary = data.probes[0]
	var ray := PhysicsRayQueryParameters3D.create(Vector3(probe.x, data.ceiling + 100, probe.z), Vector3(probe.x, data.min_height - 100, probe.z), 8)
	# Disabled collision objects may be detached from the server space until transfer.
	var terrain := world.find_child("TerrainCollision", true, false) as StaticBody3D
	_check(terrain != null and world.get_world_3d() != get_world_3d() and
		terrain.get_world_3d() == world.get_world_3d() and not terrain.can_process() and
		PhysicsServer3D.body_get_space(terrain.get_rid()) != get_world_3d().space,
		"Prepared original terrain remains disabled outside the live physics space")
	_check(get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Prebuilding does not insert original terrain into the live battle space")
	var staging := cache.prepared_viewport.get_instance_id()
	var transferred: BattleWorld = await cache.take(settings, self)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(transferred == world and world.get_parent() == self and world.native_data == data,
		"Loading transfers the same complete tree and retained resource")
	_check(PhysicsServer3D.body_get_space(terrain.get_rid()) == get_world_3d().space and
		not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),
		"Original terrain collision transfers into the live physics space")
	_check(not is_instance_id_valid(staging) and cache.prepared == null and loader.resource == null,
		"Transfer releases the staging viewport and loader ownership")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Leaving releases transferred original terrain collision")
	cache.free()
	loader.free()
	_finish()

func _settings_for(identity: Dictionary) -> Dictionary:
	var environment := {"season": identity.season, "time": "day", "weather": "clear"}
	for index in range(Content.maps.size()):
		var entry: Dictionary = Content.maps[index]
		if identity.map == entry.id or identity.map == str(entry.id) + "_swap":
			return {"map_index": index, "team_size": int(identity.teamSize), "swapped": identity.map != entry.id,
				"architecture_seed": 1, "env": environment}
	for entry: Dictionary in Content.campaign.get("maps", []):
		if entry.id != identity.map:
			continue
		var chapters: Array = Content.campaign.get("chapters", [])
		for index in range(chapters.size()):
			if chapters[index].id == entry.chapter:
				var variant: Dictionary = entry.variants[str(int(identity.teamSize))]
				return {"campaign": {"index": index, "side": entry.side, "swapped": entry.swapped},
					"architecture_seed": 1, "env": variant.config.env.duplicate(true)}
	return {}

func _finish() -> void:
	print("SEASONAL_PREBUILD assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
