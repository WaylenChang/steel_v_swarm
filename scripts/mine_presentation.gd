class_name MinePresentation
extends Node3D

var entries: Dictionary = {}
var last_check := 0.0
var wall_clock := Callable()

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
	var observed_at := float(wall_clock.call()) if wall_clock.is_valid() else now
	if observed_at - last_check < 0.12:
		return
	last_check = observed_at
	var cfg: Dictionary = Content.constants.GAME.MINES
	for visual: MeshInstance3D in entries.values():
		var distance := _distance(observer, visual.position)
		visual.visible = distance <= float(cfg.SEE_M)
		if not visual.visible:
			continue
		var opacity := minf(1, (float(cfg.SEE_M) - distance) / maxf(1, float(cfg.SEE_M) - float(cfg.CLEAR_M)))
		for surface in range(visual.mesh.get_surface_count()):
			var material: StandardMaterial3D = visual.mesh.surface_get_material(surface)
			material.albedo_color.a = opacity

static func _distance(first: Vector3, second: Vector3) -> float:
	# V8's three-argument Math.hypot compensates the normalized sum before sqrt.
	# https://github.com/nodejs/node/blob/v24.16.0/deps/v8/src/builtins/math.tq
	var a := absf(float(first.x) - float(second.x))
	var b := absf(float(first.y) - float(second.y))
	var c := absf(float(first.z) - float(second.z))
	if is_inf(a) or is_inf(b) or is_inf(c):
		return INF
	if is_nan(a) or is_nan(b) or is_nan(c):
		return NAN
	var largest := maxf(maxf(a, b), c)
	if largest == 0:
		return 0.0
	a /= largest
	b /= largest
	c /= largest
	var power_a := a * a
	var power_b := b * b
	var compensation := (power_a + power_b) - power_a - power_b
	var power_c := c * c - compensation
	return sqrt(power_a + power_b + power_c) * largest
