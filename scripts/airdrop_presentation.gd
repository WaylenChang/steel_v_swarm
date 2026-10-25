class_name AirdropPresentation
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
		var key := "airdrop_%s" % state.size
		var path := "res://assets/loot/%s.scn" % key
		if not Content.balance.get("loot_visuals", {}).has(key) or not ResourceLoader.exists(path):
			push_error("Missing original airdrop scene; regenerate and pack loot content: " + path)
			continue
		var root: Node3D = load(path).instantiate()
		root.position = state.position
		var entry := {"root": root, "ground": float(state.position.y), "born": clock, "landing": state.landing,
			"root_yaw": float(root.rotation.y)}
		for name: String in ["crate", "chute", "groundChute", "halo"]:
			entry[name] = root.find_child("n_%d" % int(Content.balance.loot_visuals[key][name]), true, false)
		entry.crate_yaw = float(entry.crate.rotation.y)
		SourceOutlineBinding.install(root)
		if not _current(token):
			root.queue_free()
			return
		entries[id] = entry
		add_child(root)
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
	var cfg: Dictionary = Content.constants.AIRDROP
	for entry: Dictionary in entries.values():
		var root: Node3D = entry.root
		# Preserve the original bornT || now branch for its zero-clock case.
		var age := clock - (float(entry.born) if entry.born != 0 else clock)
		var progress := minf(1, age / float(cfg.LAND_S)) if cfg.LAND_S > 0 else 1.0
		var landed: bool = not entry.landing or progress >= 1
		root.position.y = float(entry.ground) + (float(cfg.DROP_H) * (1 - progress) * (1 - progress) if entry.landing else 0.0)
		entry.chute.visible = not landed
		if not _current(token):
			return
		entry.groundChute.visible = landed
		if not _current(token):
			return
		entry.halo.visible = landed
		if not _current(token):
			return
		if landed:
			entry.crate_yaw += delta * 0.6
			entry.crate.quaternion = SourceQuaternion.axis_angle(Vector3.UP, float(entry.crate_yaw))
			entry.crate.position.y = sin(clock * 2 + root.position.x) * 0.14
		else:
			entry.root_yaw += delta * 0.3
			root.quaternion = SourceQuaternion.axis_angle(Vector3.UP, float(entry.root_yaw))
