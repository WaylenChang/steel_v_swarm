extends RefCounted

class FixtureResources extends RoomWorldResources:
	func request(_settings: Dictionary, _retry := false) -> int:
		return generation
	func prepare(_settings: Dictionary) -> NativeWorldData:
		return NativeWorldData.new()

class FixtureWorld extends BattleWorld:
	var build_count := 0
	var fail_build := false
	func build(map: Dictionary, _environment: Dictionary) -> void:
		build_count += 1
		bounds = map.bounds
		build_progress.emit()
		await get_tree().physics_frame
		if fail_build:
			build_error = "Fixture native scene failure"
			return
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2, 2, 2)
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		await get_tree().physics_frame
		await get_tree().physics_frame
		build_complete = true
		build_progress.emit()

class FixturePrebuild extends RoomWorldPrebuild:
	var creations := 0
	var fail_next := false
	func _create_world() -> BattleWorld:
		creations += 1
		var world := FixtureWorld.new()
		world.fail_build = fail_next
		fail_next = false
		return world

static func run(h: Node) -> void:
	var resources := FixtureResources.new()
	var cache := FixturePrebuild.new()
	cache.resources = resources
	h.add_child(resources)
	h.add_child(cache)
	var settings := {"map_index": 0, "team_size": 1, "swapped": false,
		"architecture_seed": 1, "env": {"season": "summer", "time": "day", "weather": "clear"}}
	var first := cache.request(settings)
	var renamed := settings.duplicate(true)
	renamed.room_name = "fixture"
	h._check(cache.request(renamed) == first and cache.creations == 1,
		"Room naming/roster publication reuses the same in-flight world build")
	var changed := settings.duplicate(true)
	changed.env.season = "winter"
	h._check(cache.request(changed) > first, "Season changes invalidate instantiated scenery even while the previous build is running")
	while cache.building:
		await h.get_tree().physics_frame
	var world := cache.prepared as FixtureWorld
	h._check(world != null and cache.creations == 2 and cache.failure.is_empty(),
		"Obsolete asynchronous world completion is discarded before the newest build is published")
	if world == null:
		cache.clear()
		cache.free()
		resources.free()
		return
	var retired := Node3D.new()
	h.add_child(retired)
	retired.queue_free()
	var abandoned := await cache.take(changed, retired)
	h._check(abandoned == null and cache.prepared == world,
		"An obsolete loading scene cannot consume the world intended for a replacement scene")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	h.add_child(viewport)
	var destination := Node3D.new()
	viewport.add_child(destination)
	h._check(world.get_world_3d() != destination.get_world_3d(), "Prepared collisions live in an isolated native World3D")
	h._check(_ray(destination).is_empty(), "Room preparation does not inject collision bodies into the battle physics space")
	var previous_key: Dictionary = world.get_meta("room_prebuild_identity")
	var transferred := await cache.take(changed, destination)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	h._check(transferred == world and world.get_parent() == destination and world.build_count == 1,
		"Loading transfers the same prepared world without rebuilding geometry")
	h._check(not _ray(destination).is_empty(), "Native collision bodies enter the destination World3D after transfer")
	h._check(cache.prepared == null and cache.selected.is_empty() and world.process_mode == Node.PROCESS_MODE_INHERIT,
		"Consuming a prebuild releases cache ownership and restores normal scene processing")
	var reseeded := changed.duplicate(true)
	reseeded.architecture_seed += 1
	h._check(RoomWorldPrebuild.identity(Content.battle_map(reseeded), reseeded.env, reseeded.architecture_seed) != previous_key,
		"Architecture reseeding cannot reuse an instantiated world with old placement")
	var swapped := changed.duplicate(true)
	swapped.swapped = true
	h._check(RoomWorldPrebuild.identity(Content.battle_map(swapped), swapped.env, swapped.architecture_seed) != previous_key,
		"Reversed bases and lanes invalidate native world prebuilding")
	cache.request(settings)
	cache.clear()
	while cache.building:
		await h.get_tree().physics_frame
	h._check(cache.prepared == null and cache.selected.is_empty() and cache.failure.is_empty(),
		"Leaving while a world is building retires the isolated scene without stale readiness")
	var notifications: Array = []
	cache.changed.connect(func(): notifications.append({"failed": not cache.failure.is_empty(), "ready": is_instance_valid(cache.prepared), "selected": not cache.selected.is_empty()}))
	cache.fail_next = true
	cache.request(settings)
	while cache.building:
		await h.get_tree().physics_frame
	h._check(not cache.failure.is_empty() and notifications.back().failed,
		"An asynchronous scene failure publishes a room status change without requiring another roster packet")
	var retried := await cache.take(settings, destination)
	h._check(retried != null and cache.failure.is_empty(), "Loading retries a failed native scene build before consuming the replacement")
	h._check(notifications.any(func(item): return item.ready) and not notifications.back().selected,
		"Ready and consumed notifications let the independent room preload indicator update and clear")
	viewport.free()
	cache.free()
	resources.free()

static func _ray(root: Node3D) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 3, 0), Vector3(0, -3, 0), 1))
