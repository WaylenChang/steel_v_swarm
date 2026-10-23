class_name LootPresentation
extends Node3D

var entries: Dictionary = {}
var clock := 0.0

func sync(states: Array, now: float) -> void:
	clock = now
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
		add_child(visual)
		visual.position = state.position
		var body: Node3D = visual.find_child("n_%d" % int(Content.balance.loot_visuals[key].body), true, false)
		SourceOutlineBinding.install(visual)
		entries[id] = {"root": visual, "body": body}
	for id: int in entries.keys():
		if not seen.has(id):
			entries[id].root.queue_free()
			entries.erase(id)

func _process(delta: float) -> void:
	clock += delta
	for entry: Dictionary in entries.values():
		var root: Node3D = entry.root
		root.rotation.y += delta * 1.6
		entry.body.position.y = 1.0 + sin(clock * 2.2 + root.position.x) * 0.18
