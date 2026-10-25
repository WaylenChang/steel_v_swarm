class_name FirePresentation
extends Node3D

var entries: Dictionary = {}
var dynamics: Dictionary = {}
var clock := 0.0
var wall_clock := Callable()

func sync(states: Array, now: float, weather: Dictionary) -> void:
	clock = float(wall_clock.call()) if wall_clock.is_valid() else now
	dynamics = weather
	var seen := {}
	for state: Dictionary in states:
		var id := int(state.id)
		seen[id] = true
		var key: String = "fire_lightning" if state.lightning else state.kind
		if not entries.has(id):
			var path := "res://assets/hazards/%s.scn" % key
			if not Content.balance.get("hazard_visuals", {}).has(key) or not ResourceLoader.exists(path):
				push_error("Missing original fire scene; regenerate and pack hazard content: " + path)
				continue
			var visual: Node3D = load(path).instantiate()
			add_child(visual)
			var nodes := {visual.name: visual}
			for node: Node3D in visual.find_children("*", "Node3D", true, false):
				nodes[node.name] = node
				node.rotation_order = EULER_ORDER_XYZ
				if node is MeshInstance3D:
					node.mesh = node.mesh.duplicate(true)
			SourceOutlineBinding.install(visual)
			entries[id] = {"root": visual, "nodes": nodes, "fx": Content.balance.hazard_visuals[key].fx}
		var root: Node3D = entries[id].root
		root.position = state.position
		root.scale = Vector3.ONE * float(state.scale) * float(Content.constants.HAZARDS[state.kind].r) / float(Content.balance.hazard_visuals[key].radius)
	for id: int in entries.keys():
		if not seen.has(id):
			entries[id].root.queue_free()
			entries.erase(id)

func _opacity(node: MeshInstance3D, opacity: float, disable_depth_write: bool = false) -> void:
	for surface in range(node.mesh.get_surface_count()):
		var material: StandardMaterial3D = node.mesh.surface_get_material(surface)
		material.albedo_color.a = opacity
		if disable_depth_write:
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			material.set_meta("source_depth_write", false)

func _process(delta: float) -> void:
	clock = float(wall_clock.call()) if wall_clock.is_valid() else clock + delta
	var strength := EnvironmentRules.fire_multiplier(dynamics)
	var wind := clampf(float(dynamics.get("wind", 0)) / 100, 0, 1)
	var direction: Array = dynamics.get("windDir", [1, 0])
	for entry: Dictionary in entries.values():
		for flame: Dictionary in entry.fx.flames:
			var node: MeshInstance3D = entry.nodes["n_%d" % int(flame.id)]
			node.visible = strength > 0
			if not node.visible:
				continue
			var flicker := 0.82 + 0.18 * sin(clock * 8 + float(flame.phase)) + 0.1 * sin(clock * 19 + float(flame.phase) * 2)
			var height := flicker * sqrt(strength)
			var size: Array = flame.scale
			node.scale = Vector3(float(size[0]) / sqrt(flicker), float(size[1]) * height, float(size[2]) / sqrt(flicker))
			node.position = Vector3(flame.origin[0], float(flame.origin[1]) + float(flame.height) * (height - 1) / 2, flame.origin[2])
			node.rotation.z = -float(direction[0]) * wind * 0.32
			node.rotation.x = float(direction[1]) * wind * 0.32
			_opacity(node, float(flame.opacity) * minf(1, strength * 2))
		for index in range(entry.fx.smoke.size()):
			var smoke: Dictionary = entry.fx.smoke[index]
			var node: MeshInstance3D = entry.nodes["n_%d" % int(smoke.id)]
			node.visible = strength > 0
			if not node.visible:
				continue
			var life := fmod(clock * 0.16 + index * 0.31, 1)
			node.position = Vector3(float(smoke.origin[0]) + float(direction[0]) * wind * life * 7,
				float(smoke.origin[1]) + life * 6, float(smoke.origin[2]) + float(direction[1]) * wind * life * 7)
			var size := 0.65 + life * 0.9
			node.scale = Vector3(float(smoke.scale[0]) * size, float(smoke.scale[1]) * size, float(smoke.scale[2]) * size)
			_opacity(node, float(smoke.opacity) * sin(life * PI) * minf(1, strength), true)
