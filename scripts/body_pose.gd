class_name BodyPose
extends RefCounted

var states: Dictionary = {}

func configure(nodes: Dictionary) -> void:
	states.clear()
	for node: Node3D in nodes.values():
		register(node)

func register(node: Node3D) -> void:
	var rest: Dictionary = node.get_meta("source_trs")
	states[node.get_instance_id()] = {"p": vector(rest.p), "q": quaternion(rest.q), "s": vector(rest.s),
		"r": rest.r.duplicate(), "signature": node.transform}

func read(node: Node3D) -> Dictionary:
	var state: Dictionary = states[node.get_instance_id()]
	if state.signature == node.transform:
		return state
	# Preserve the source reflection axes when native code changes a joint matrix.
	var basis := node.basis
	var signs: Vector3 = state.s.sign()
	var size := Vector3(basis.x.length(), basis.y.length(), basis.z.length()) * signs
	assert(size.x != 0 and size.y != 0 and size.z != 0, "Write singular body poses through BodyPose")
	assert(signf(size.x * size.y * size.z) == signf(basis.determinant()), "Write body reflection changes through BodyPose")
	var rotation := SourceQuaternion.from_scaled(basis, [size.x, size.y, size.z])
	state.p = node.position
	state.q = rotation
	state.r = SourceEuler.from_quaternion(rotation, SourceEuler.ORDERS[node.rotation_order])
	state.s = size
	state.signature = node.transform
	return state

func write(node: Node3D, position: Vector3, rotation: Quaternion, size: Vector3) -> void:
	var state := {"p": position, "q": rotation, "s": size,
		"r": SourceEuler.from_quaternion(rotation, SourceEuler.ORDERS[node.rotation_order])}
	_apply(node, state)

func set_scale(node: Node3D, size: Vector3) -> void:
	var state := read(node)
	state.s = size
	_apply(node, state)

func set_position(node: Node3D, position: Vector3) -> void:
	var state := read(node)
	state.p = position
	_apply(node, state)

func rotation(node: Node3D) -> Array:
	return read(node).r.duplicate()

func set_rotation(node: Node3D, angles: Array) -> void:
	var state := read(node)
	state.r = angles.duplicate()
	state.q = WeaponPresentation.source_rotation({"rotation": angles, "order": SourceEuler.ORDERS[node.rotation_order]})
	_apply(node, state)

func set_quaternion(node: Node3D, value: Quaternion) -> void:
	var state := read(node)
	write(node, state.p, value, state.s)

func set_axis(node: Node3D, axis: String, angle: float) -> void:
	var angles := rotation(node)
	angles[WeaponPresentation.axis_index(axis)] = angle
	set_rotation(node, angles)

func axis(node: Node3D, component: String) -> float:
	return read(node).r[WeaponPresentation.axis_index(component)]

func add_axis(node: Node3D, component: String, amount: float) -> void:
	set_axis(node, component, axis(node, component) + amount)

func position_axis(node: Node3D, component: String) -> float:
	return read(node).p[WeaponPresentation.axis_index(component)]

func set_position_axis(node: Node3D, component: String, value: float) -> void:
	var position: Vector3 = read(node).p
	position[WeaponPresentation.axis_index(component)] = value
	set_position(node, position)

func set_channel(node: Node3D, channel: String, component: String, value: float) -> void:
	match channel:
		"rotation":
			set_axis(node, component, value)
		"position":
			set_position_axis(node, component, value)
		"scale":
			var size: Vector3 = read(node).s
			size[WeaponPresentation.axis_index(component)] = value
			set_scale(node, size)
		_:
			assert(false, "Unsupported source rigid-motion channel: " + channel)

func _apply(node: Node3D, state: Dictionary) -> void:
	node.transform = Transform3D(SourceQuaternion.basis(state.q).scaled_local(state.s), state.p)
	state.signature = node.transform
	states[node.get_instance_id()] = state

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

static func quaternion(values: Array) -> Quaternion:
	return Quaternion(values[0], values[1], values[2], values[3])

static func named(root: Node3D, source_name: String) -> Node3D:
	if root.get_meta("source_name", "") == source_name:
		return root
	for child: Node3D in root.get_children():
		var found := named(child, source_name)
		if found != null:
			return found
	return null
