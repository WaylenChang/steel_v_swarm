extends RefCounted

class FixtureResources extends RoomWorldResources:
	func path_for(settings: Dictionary) -> String:
		return settings.path

static func run(h: Node) -> void:
	var full := WorldVariant.select_required()
	h._check(full.error.is_empty() and full.worlds == WorldVariant.required(), "Default world verification retains the complete source manifest")
	var selected_path := "res://assets/worlds/berlin_1_spring.res"
	var selected := WorldVariant.select_required(["--bundle=berlin_1_spring"])
	h._check(selected.error.is_empty() and selected.worlds.size() == 1 and selected.worlds.has(selected_path), "Incremental native generation and verification select the same original bundle")
	selected = WorldVariant.select_required(["berlin", "--bundle=berlin_1_spring", "--bundle=berlin_1_spring"])
	h._check(selected.error.is_empty() and selected.worlds.size() == 1, "Repeated bundle arguments retain one original manifest entry")
	selected = WorldVariant.select_required(["berlin_swap", "--bundle=berlin_swap_1_spring"])
	h._check(selected.error.is_empty() and selected.worlds.size() == 1 and selected.worlds.has("res://assets/worlds/berlin_swap_1_spring.res"), "Swapped source map IDs select their authored base assignment independently")
	for arguments: Array in [["--bundle=missing"], ["madrid", "--bundle=berlin_1_spring"], ["--bundle=../berlin_1_spring"], ["--bundle="], ["berlin", "unknown_map"]]:
		selected = WorldVariant.select_required(arguments)
		h._check(not selected.error.is_empty() and selected.worlds.is_empty(), "Invalid or conflicting bundle selection never falls back to a different world")
	var identity := WorldVariant.identity("res://assets/worlds/berlin_1.res", {"season": "spring"})
	h._check(WorldVariant.matches_identity(identity, identity), "Native seasonal identities accept integral team sizes")
	h._check(WorldVariant.matches_identity(JSON.parse_string(JSON.stringify(identity)), identity), "Captured JSON seasonal identities accept the same numeric team size")
	for invalid: Variant in [null, {}, {"map": "berlin", "season": "spring", "teamSize": "1"},
		{"map": "berlin", "season": "spring", "teamSize": true}, {"map": "berlin", "season": "spring", "teamSize": 1.5},
		{"map": "berlin", "season": "spring", "teamSize": NAN}, {"map": "berlin", "season": "spring", "teamSize": INF},
		{"map": "madrid", "season": "spring", "teamSize": 1}, {"map": "berlin", "season": "summer", "teamSize": 1},
		{"map": "berlin", "season": "spring", "teamSize": 1, "extra": true}]:
		h._check(not WorldVariant.matches_identity(invalid, identity), "Invalid or mismatched captured seasonal identities reject without numeric coercion")
	var prefix := "user://room-resource-%d" % Time.get_ticks_usec()
	var first := prefix + "-first.res"
	var second := prefix + "-second.res"
	var missing := prefix + "-missing.res"
	for path: String in [first, second]:
		h._check(_save(path) == OK, "Prepare independent native ResourceLoader lifecycle fixtures")
	var loader := FixtureResources.new()
	h.add_child(loader)
	var initial := loader.request({"path": first})
	h._check(loader.request({"path": first}) == initial, "Repeated room publication retains one in-flight native resource request")
	var changed := loader.request({"path": second})
	h._check(changed > initial, "Changed room resources invalidate the old consumer")
	var result: NativeWorldData = await loader.prepare({"path": second})
	h._check(result != null and result.resource_path == second, "An older completed resource load cannot replace the latest room resource")
	h._check(loader.request({"path": second}) == changed and loader.resource == result,
		"Room-to-loading transition retains the native resource and its dependency cache")
	loader.clear()
	h._check(loader.resource == null and loader.desired.is_empty(), "Leaving releases room resource ownership")
	loader.request({"path": first})
	loader.clear()
	while loader.loading:
		await h.get_tree().process_frame
	h._check(loader.resource == null and loader.failure.is_empty(), "A cancelled consumer drains its live Godot request without publishing stale readiness")
	loader.request({"path": missing})
	h._check(not loader.failure.is_empty() and loader.resource == null, "Missing native worlds fail explicitly during room preload")
	h._check(_save(missing) == OK, "Prepare recovery of an unavailable native resource")
	result = await loader.prepare({"path": missing})
	h._check(result != null and loader.failure.is_empty(), "Entering loading retries a failed room preload through the same native loader")
	loader.clear()
	loader.free()
	result = null
	for path: String in [first, second, missing]:
		h._check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only this native loader test's temporary resource")

static func _save(path: String) -> Error:
	var data := NativeWorldData.new()
	var node := Node3D.new()
	data.scene = PackedScene.new()
	var error := data.scene.pack(node)
	node.free()
	return ResourceSaver.save(data, path) if error == OK else error
