class_name LootPresentation
extends "res://scripts/collectible_presentation.gd"

func sync(states: Array, now: float) -> void:
	if not _active():
		return
	revision += 1
	var token := revision
	if not _sample_clock(now, token):
		return
	var seen := {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		if entries.has(id):
			continue
		var key := "ammo" if state.get("ammo", false) else "affix" if state.has("affix") else "cash"
		var path := "res://assets/loot/%s.scn" % key
		if not Content.balance.get("loot_visuals", {}).has(key) or not ResourceLoader.exists(path):
			push_error("Missing original loot scene; regenerate and pack loot content: " + path)
			continue
		var visual: Node3D = load(path).instantiate()
		visual.position = state.position
		var body: Node3D = visual.find_child("n_%d" % int(Content.balance.loot_visuals[key].body), true, false)
		SourceOutlineBinding.install(visual)
		if not _current(token):
			visual.queue_free()
			return
		entries[id] = {"root": visual, "body": body, "yaw": float(visual.rotation.y)}
		add_child(visual)
		if not _current(token):
			return
	for id: int in entries.keys():
		if not seen.has(id):
			_release_entry(id)
			if not _current(token):
				return

func _process(delta: float) -> void:
	var token := revision
	if not _sample_clock(clock + delta, token):
		return
	for entry: Dictionary in entries.values():
		var root: Node3D = entry.root
		entry.yaw += delta * 1.6
		root.quaternion = SourceQuaternion.axis_angle(Vector3.UP, float(entry.yaw))
		if not _current(token):
			return
		entry.body.position.y = 1.0 + sin(clock * 2.2 + root.position.x) * 0.18
