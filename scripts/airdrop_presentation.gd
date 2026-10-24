class_name AirdropPresentation
extends Node3D

var entries: Dictionary = {}
var clock := 0.0
var wall_clock := Callable()

func sync(states: Array, now: float) -> void:
	clock = float(wall_clock.call()) if wall_clock.is_valid() else now
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
		add_child(root)
		root.position = state.position
		var entry := {"root": root, "ground": float(state.position.y), "born": clock, "landing": state.landing,
			"root_yaw": float(root.rotation.y)}
		for name: String in ["crate", "chute", "groundChute", "halo"]:
			entry[name] = root.find_child("n_%d" % int(Content.balance.loot_visuals[key][name]), true, false)
		entry.crate_yaw = float(entry.crate.rotation.y)
		SourceOutlineBinding.install(root)
		entries[id] = entry
	for id: int in entries.keys():
		if not seen.has(id):
			entries[id].root.queue_free()
			entries.erase(id)

func _process(delta: float) -> void:
	clock = float(wall_clock.call()) if wall_clock.is_valid() else clock + delta
	var cfg: Dictionary = Content.constants.AIRDROP
	for entry: Dictionary in entries.values():
		var root: Node3D = entry.root
		# Preserve the original bornT || now branch for its zero-clock case.
		var age := clock - (float(entry.born) if entry.born != 0 else clock)
		var progress := minf(1, age / float(cfg.LAND_S)) if cfg.LAND_S > 0 else 1.0
		var landed: bool = not entry.landing or progress >= 1
		root.position.y = float(entry.ground) + (float(cfg.DROP_H) * (1 - progress) * (1 - progress) if entry.landing else 0.0)
		entry.chute.visible = not landed
		entry.groundChute.visible = landed
		entry.halo.visible = landed
		if landed:
			entry.crate_yaw += delta * 0.6
			entry.crate.quaternion = SourceQuaternion.axis_angle(Vector3.UP, float(entry.crate_yaw))
			entry.crate.position.y = sin(clock * 2 + root.position.x) * 0.14
		else:
			entry.root_yaw += delta * 0.3
			root.quaternion = SourceQuaternion.axis_angle(Vector3.UP, float(entry.root_yaw))
