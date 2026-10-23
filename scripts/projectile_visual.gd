class_name ProjectileVisual
extends Node3D

var profile: Dictionary
var source_root: Node3D
var nodes: Dictionary = {}
var animated_materials: Dictionary = {}

func configure(key: String) -> void:
	profile = Content.balance.projectileVisual.profiles[key]
	source_root = (load("res://assets/projectiles/%s.scn" % key) as PackedScene).instantiate()
	add_child(source_root)
	_collect(source_root)
	var animated: Array = profile.authored.duplicate()
	for jet: Dictionary in profile.jets:
		animated.append(int(jet.node))
	for id in animated:
		var mesh: MeshInstance3D = nodes[int(id)]
		# Source projectiles share geometry, but each live opacity animation owns its material.
		var material := mesh.get_active_material(0).duplicate() as StandardMaterial3D
		mesh.set_surface_override_material(0, material)
		animated_materials[int(id)] = material
	SourceOutlineBinding.install(source_root)

func _collect(node: Node3D) -> void:
	if node.get_meta("source_outline_helper", false):
		return
	nodes[int(String(node.name).trim_prefix("n_"))] = node
	for child: Node3D in node.get_children():
		_collect(child)

func place(point: Vector3, direction: Vector3, age: float, speed: float) -> void:
	position = point
	if direction.length_squared() > 0.000001:
		quaternion = Quaternion(Vector3.BACK, direction.normalized())
	step_fx(age, speed)

func step_fx(age: float, speed: float) -> void:
	if not is_finite(age) or not is_finite(speed):
		return
	var thrust := 0.82 + minf(1, maxf(0, speed) / 260) * 0.28
	for id in profile.authored:
		_set_opacity(int(id), 0.65 + 0.2 * sin(age * 37 + profile.phase))
	if int(profile.wake) >= 0:
		var wake: Node3D = nodes[int(profile.wake)]
		var length: float = (4.0 if profile.heavy else 2.4) * thrust
		var radius: float = (0.14 if profile.heavy else 0.075) * (1 + sin(age * 25) * 0.08)
		wake.scale = Vector3(radius, length, radius)
		wake.position.z = -length * 0.5
	for index in range(profile.jets.size()):
		var jet: Dictionary = profile.jets[index]
		var mesh: Node3D = nodes[int(jet.node)]
		var flick: float = 1 + sin(age * (31 + index * 7) + profile.phase + index * 1.9) * (0.09 if index else 0.15)
		mesh.scale = Vector3(jet.rad * (0.92 + flick * 0.08), jet.len * thrust * flick, jet.rad * (0.92 + flick * 0.08))
		mesh.position.z = jet.nozzle - mesh.scale.y * 0.5
		_set_opacity(int(jet.node), jet.opacity * (0.82 + flick * 0.18))

func _set_opacity(id: int, opacity: float) -> void:
	var material: StandardMaterial3D = animated_materials[id]
	var color := material.albedo_color
	color.a = opacity
	material.albedo_color = color
