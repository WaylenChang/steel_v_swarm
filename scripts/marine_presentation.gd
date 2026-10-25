class_name MarinePresentation
extends RefCounted

const BindingLifetime = preload("res://scripts/scenery_binding_lifetime.gd")

# Original toon.js ripple slots/cooldown survive world disposal, just like its wind clock.
static var ripples := MarineRippleState.new()
var waves := MarineWaveSources.new()
var bounds: Dictionary
var water_height: Callable
var environment_code: Callable
var swamp_cells: Array = []
var swamp_pending: Array = []
var swamp_z := 0.0
var swamp_ready := false
var bindings: Array[MarineShaderBinding] = []
var reflections: Array = []
var appearance: Dictionary = {}
var visual_revision := -1
var source_root: Node3D
var bound := false
var configured := false
var retired := false
var generation := 0
var revision := 0
var lifetime: BindingLifetime
var lifetime_id := 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(lifetime):
		lifetime.controller = null
		lifetime.queue_free()

func _active() -> bool:
	return not retired and (not bound or (is_instance_valid(source_root) and not source_root.is_queued_for_deletion()))

func _current(token: int) -> bool:
	return _active() and revision == token

func _release_surfaces() -> void:
	var previous := bindings.duplicate()
	bindings.clear()
	reflections.clear()
	appearance = {}
	visual_revision = -1
	source_root = null
	if is_instance_valid(lifetime):
		lifetime.controller = null
		lifetime.queue_free()
	lifetime = null
	lifetime_id = 0
	for binding: MarineShaderBinding in previous:
		binding.retire()

func _retire_binding(binding_generation: int, binding_instance: int) -> void:
	if generation != binding_generation or lifetime_id != binding_instance:
		return
	lifetime = null
	retire()

func retire() -> void:
	if retired:
		return
	retired = true
	generation += 1
	revision += 1
	configured = false
	water_height = Callable()
	environment_code = Callable()
	bounds = {}
	swamp_cells.clear()
	swamp_pending.clear()
	swamp_ready = false
	waves.sources.clear()
	waves.shapes.clear()
	_release_surfaces()

func bind_surfaces(root: Node3D, source: Dictionary, depth_field: Texture2D) -> bool:
	if retired or not is_instance_valid(root) or root.is_queued_for_deletion():
		return false
	generation += 1
	revision += 1
	var token := revision
	_release_surfaces()
	bound = true
	source_root = root
	lifetime = BindingLifetime.new()
	lifetime_id = lifetime.get_instance_id()
	lifetime.controller = weakref(self)
	lifetime.generation = generation
	root.add_child(lifetime)
	if not _current(token):
		return false
	appearance = source.get("appearance", {})
	if appearance.is_empty():
		push_error("Missing original marine appearance declarations")
		return false
	visual_revision = -1
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not node.get_meta("source_water", false):
			continue
		var overrides: Array[MarineShaderBinding] = []
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as ShaderMaterial
			if original == null or not original.has_meta("source_marine"):
				push_error("Original water geometry requires its captured native marine shader")
				return false
			var binding := MarineShaderBinding.new()
			if not binding.configure(original, original.get_meta("source_marine"), source, depth_field, ripples.packets):
				return false
			if not binding.configure_geometry(node.get_meta("source_marine_frame", []), bool(node.get_meta("source_marine_receive_shadow", false))):
				return false
			overrides.append(binding)
		node.material_override = null
		if not _current(token):
			return false
		for surface in range(overrides.size()):
			node.set_surface_override_material(surface, overrides[surface].material)
			if not _current(token):
				return false
			bindings.append(overrides[surface])
			if overrides[surface].material.get_meta("source_marine").reflection:
				reflections.append({"node": node, "binding": overrides[surface],
					"opacity": float(overrides[surface].material.get_shader_parameter("uNativeOpacity"))})
		if not node.get_meta("source_marine_frustum_culled", true):
			RenderingServer.instance_set_ignore_culling(node.get_instance(), true)
	sync_visuals(Visuals)
	return _current(token)

func sync_visuals(preferences: VisualPreferences) -> void:
	if not _active() or preferences.rules.is_empty() or appearance.is_empty() or preferences.revision == visual_revision:
		return
	var token := revision
	for binding: MarineShaderBinding in bindings:
		binding.sync_visuals(preferences, appearance)
		if not _current(token):
			return
	var amount := float(preferences.value("reflect"))
	for reflection: Dictionary in reflections:
		reflection.node.visible = amount > 0
		if not _current(token):
			return
		if amount > 0:
			reflection.binding.material.set_shader_parameter("uNativeOpacity", float(reflection.opacity) * minf(1, amount))
			if not _current(token):
				return
	visual_revision = preferences.revision

func sync_lighting(presentation: WeatherPresentation) -> void:
	if not _active():
		return
	var token := revision
	for binding: MarineShaderBinding in bindings:
		binding.sync_lighting(presentation)
		if not _current(token):
			return

func configure(source: Dictionary, rectangle: Dictionary, water: Callable, code: Callable) -> bool:
	if not _active():
		return false
	if not source.get("wind") is Dictionary:
		push_error("Missing original marine wind/wave declarations")
		return false
	if not waves.configure(int(source.wind.get("SEA_SOURCE_N", 0)), source.get("sources", []), source.get("shapes", [])) or not ripples.configure(source.wind):
		return false
	revision += 1
	bounds = rectangle.duplicate()
	water_height = water
	environment_code = code
	swamp_cells.clear()
	swamp_pending.clear()
	swamp_z = float(bounds.minZ)
	swamp_ready = false
	configured = true
	return true

func advance(delta: float, now: float, weather: Dictionary, motions: Array[SceneryMotion]) -> void:
	if not configured or not _active():
		return
	revision += 1
	var token := revision
	sync_visuals(Visuals)
	if not _current(token):
		return
	waves.update_vessels(motions, float(weather.get("waveAmp", 1)) <= 0.001)
	if not _scan_swamp(token):
		return
	ripples.advance(swamp_cells if swamp_ready else [], delta, now)
	for binding: MarineShaderBinding in bindings:
		binding.advance(weather, waves, ripples)
		if not _current(token):
			return

func _scan_swamp(token: int) -> bool:
	if swamp_ready:
		return true
	var water: Variant = water_height.call()
	if not _current(token):
		return false
	if water == null:
		return true
	var rows := ceili((float(bounds.maxZ) - float(bounds.minZ)) / 20)
	var per_frame := maxi(1, ceili(float(rows) / 6))
	var done := 0
	while swamp_z < float(bounds.maxZ) and done < per_frame:
		var x := float(bounds.minX)
		while x < float(bounds.maxX):
			var code := int(environment_code.call(x, swamp_z))
			if not _current(token):
				return false
			if code == 2:
				swamp_pending.append({"x": x, "z": swamp_z})
			x += 20
		swamp_z += 20
		done += 1
	if swamp_z >= float(bounds.maxZ):
		swamp_cells = swamp_pending
		swamp_pending = []
		swamp_ready = true
	return _current(token)
