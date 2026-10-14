class_name MinePresentation
extends Node3D

var entries: Dictionary = {}
var last_check := -100.0

func sync(states: Array) -> void:
	var seen := {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		if entries.has(id):
			continue
		var path := "res://assets/hazards/mine_bump.scn"
		if not ResourceLoader.exists(path):
			push_error("Missing original mine model; regenerate and pack hazard content")
			continue
		var visual: MeshInstance3D = load(path).instantiate()
		visual.mesh = visual.mesh.duplicate(true)
		add_child(visual)
		visual.position = state.position
		entries[id] = visual
	for id: int in entries.keys():
		if not seen.has(id):
			entries[id].queue_free()
			entries.erase(id)

func update_view(observer: Vector3, now: float) -> void:
	if now - last_check < 0.12:
		return
	last_check = now
	var cfg: Dictionary = Content.constants.GAME.MINES
	for visual: MeshInstance3D in entries.values():
		var distance := observer.distance_to(visual.position)
		visual.visible = distance <= float(cfg.SEE_M)
		if not visual.visible:
			continue
		var opacity := minf(1, (float(cfg.SEE_M) - distance) / maxf(1, float(cfg.SEE_M) - float(cfg.CLEAR_M)))
		for surface in range(visual.mesh.get_surface_count()):
			var material: StandardMaterial3D = visual.mesh.surface_get_material(surface)
			material.albedo_color.a = opacity
