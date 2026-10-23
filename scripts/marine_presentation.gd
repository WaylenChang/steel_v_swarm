class_name MarinePresentation
extends RefCounted

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

func bind_surfaces(root: Node3D, source: Dictionary, depth_field: Texture2D) -> bool:
	bindings.clear()
	reflections.clear()
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
		for surface in range(overrides.size()):
			node.set_surface_override_material(surface, overrides[surface].material)
			bindings.append(overrides[surface])
			if overrides[surface].material.get_meta("source_marine").reflection:
				reflections.append({"node": node, "binding": overrides[surface],
					"opacity": float(overrides[surface].material.get_shader_parameter("uNativeOpacity"))})
		if not node.get_meta("source_marine_frustum_culled", true):
			RenderingServer.instance_set_ignore_culling(node.get_instance(), true)
	sync_visuals(Visuals)
	return true

func sync_visuals(preferences: VisualPreferences) -> void:
	if preferences.rules.is_empty() or appearance.is_empty() or preferences.revision == visual_revision:
		return
	for binding: MarineShaderBinding in bindings:
		binding.sync_visuals(preferences, appearance)
	var amount := float(preferences.value("reflect"))
	for reflection: Dictionary in reflections:
		reflection.node.visible = amount > 0
		if amount > 0:
			reflection.binding.material.set_shader_parameter("uNativeOpacity", float(reflection.opacity) * minf(1, amount))
	visual_revision = preferences.revision

func sync_lighting(presentation: WeatherPresentation) -> void:
	for binding: MarineShaderBinding in bindings:
		binding.sync_lighting(presentation)

func configure(source: Dictionary, rectangle: Dictionary, water: Callable, code: Callable) -> bool:
	if not source.get("wind") is Dictionary:
		push_error("Missing original marine wind/wave declarations")
		return false
	if not waves.configure(int(source.wind.get("SEA_SOURCE_N", 0)), source.get("sources", []), source.get("shapes", [])) or not ripples.configure(source.wind):
		return false
	bounds = rectangle.duplicate()
	water_height = water
	environment_code = code
	swamp_cells.clear()
	swamp_pending.clear()
	swamp_z = float(bounds.minZ)
	swamp_ready = false
	return true

func advance(delta: float, now: float, weather: Dictionary, motions: Array[SceneryMotion]) -> void:
	sync_visuals(Visuals)
	waves.update_vessels(motions, float(weather.get("waveAmp", 1)) <= 0.001)
	_scan_swamp()
	ripples.advance(swamp_cells if swamp_ready else [], delta, now)
	for binding: MarineShaderBinding in bindings:
		binding.advance(weather, waves, ripples)

func _scan_swamp() -> void:
	if swamp_ready or water_height.call() == null:
		return
	var rows := ceili((float(bounds.maxZ) - float(bounds.minZ)) / 20)
	var per_frame := maxi(1, ceili(float(rows) / 6))
	var done := 0
	while swamp_z < float(bounds.maxZ) and done < per_frame:
		var x := float(bounds.minX)
		while x < float(bounds.maxX):
			if int(environment_code.call(x, swamp_z)) == 2:
				swamp_pending.append({"x": x, "z": swamp_z})
			x += 20
		swamp_z += 20
		done += 1
	if swamp_z >= float(bounds.maxZ):
		swamp_cells = swamp_pending
		swamp_pending = []
		swamp_ready = true
