class_name FirePresentation
extends Node3D

var entries: Dictionary = {}
var dynamics: Dictionary = {}
var clock := 0.0

func sync(states: Array, now: float, weather: Dictionary) -> void:
	clock = now
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

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _opacity(node: MeshInstance3D, opacity: float) -> void:
	for surface in range(node.mesh.get_surface_count()):
		var material: StandardMaterial3D = node.mesh.surface_get_material(surface)
		material.albedo_color.a = opacity

func _process(delta: float) -> void:
	clock += delta
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
			var size := _vector(flame.scale)
			node.scale = Vector3(size.x / sqrt(flicker), size.y * height, size.z / sqrt(flicker))
			node.position = _vector(flame.origin) + Vector3.UP * float(flame.height) * (height - 1) / 2
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
			node.position = _vector(smoke.origin) + Vector3(float(direction[0]) * wind * life * 7, life * 6, float(direction[1]) * wind * life * 7)
			node.scale = _vector(smoke.scale) * (0.65 + life * 0.9)
			_opacity(node, float(smoke.opacity) * sin(life * PI) * minf(1, strength))
