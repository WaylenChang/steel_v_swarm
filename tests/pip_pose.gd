extends "res://tests/pip_composition.gd"

var orientation_gate := false

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip.json")
	var composition: Dictionary = Content.read_json("res://tests/fixtures/pip_composition.json")
	_check(composition.get("poseCases") is Array and composition.poseCases.size() == 26,
		"PiP camera retains the original browser pose boundary cases")
	if failures > 0:
		_finish_pose()
		return
	_check_pip_source_identity(capture, composition)
	if failures == 0:
		_check_poses(composition.poseCases, capture.rules)
	_finish_pose()

func _check_poses(cases: Array, rules: Dictionary) -> void:
	var previous_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	var stage := SubViewport.new()
	stage.world_3d = World3D.new()
	add_child(stage)
	var battle := BattleSimulation.new()
	stage.add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.hp = 1
	battle.add_child(pilot)
	var actor := BattleUnit.new()
	actor.entity_id = 7
	actor.peer_id = pilot.peer_id
	actor.hp = 1
	actor.special = {"owner_peer": pilot.peer_id}
	battle.add_child(actor)
	actor.model = Node3D.new()
	actor.add_child(actor.model)
	battle.units[actor.entity_id] = actor
	var view := PipView.new()
	stage.add_child(view)
	var reference_camera: Camera3D
	if orientation_gate:
		reference_camera = Camera3D.new()
		stage.add_child(reference_camera)
	var large_bases: Array[Basis] = []
	var orientation_report: Array = []
	for index in cases.size():
		failure_scope = "pip_pose_%d" % index
		var sample: Dictionary = cases[index]
		var size := Vector2(float(sample.size[0]), float(sample.size[1]))
		var position := Vector3(float(sample.position[0]), float(sample.position[1]), float(sample.position[2]))
		var draw: Dictionary = sample.draw
		var yaw := str(sample.yawBits).hex_decode().decode_double(0)
		var expected := Vector3(str(draw.positionFloat32Bits[0]).hex_decode().decode_float(0),
			str(draw.positionFloat32Bits[1]).hex_decode().decode_float(0), str(draw.positionFloat32Bits[2]).hex_decode().decode_float(0))
		var offset := float(rules.DECOY_EYE if sample.decoy else rules.HERO_EYE)
		_check(float(position.y) + offset == str(draw.positionBits[1]).hex_decode().decode_double(0),
			"Original PiP eye offset is added in double precision before native storage: " + str(sample.position[1]) + " offset=" + str(offset) + " source=" + str(draw.position[1]))
		var plan := PipViewState.frame(size, 0, position, yaw, bool(sample.decoy), rules)
		_check(plan.position == expected, "PiP camera eye matches the source Float32 pose: " + str(sample.position[1]))
		var rect: Rect2 = plan.rect
		_check(rect.position == Vector2(float(draw.rect[0]), float(draw.rect[1])) and rect.size == Vector2(float(draw.rect[2]), float(draw.rect[3])),
			"PiP camera retains the captured original viewport")
		_check(float(plan.yaw) == yaw and float(plan.fov) == float(draw.fov), "PiP camera retains source yaw and FOV")
		stage.size = Vector2i(int(size.x), int(size.y))
		pilot.kind = "robot" if sample.decoy else "drone"
		actor.kind = "decoy" if sample.decoy else "drone"
		actor.character = "" if sample.decoy else "s01"
		actor.yaw = yaw
		actor.model.position = position
		view.update_view(battle, pilot, "STEEL")
		_check(not view.views.is_empty(), "Source-selected PiP camera is available")
		if not view.views.is_empty():
			_check(view.views[0].camera.global_position == expected, "Rendered PiP camera stores the original source eye position")
			if sample.decoy and index in [8, 9]:
				large_bases.append(view.views[0].camera.global_basis)
			if orientation_gate:
				var source_quaternion := Quaternion(str(draw.quaternionBits[0]).hex_decode().decode_double(0),
					str(draw.quaternionBits[1]).hex_decode().decode_double(0), str(draw.quaternionBits[2]).hex_decode().decode_double(0),
					str(draw.quaternionBits[3]).hex_decode().decode_double(0))
				reference_camera.global_transform = Transform3D(SourceQuaternion.basis(source_quaternion), expected)
				var quaternion_matches: bool = view.views[0].camera.global_basis == reference_camera.global_basis
				_check(quaternion_matches,
					"PiP camera keeps the original yaw through the native quaternion boundary")
				var actual_basis: Basis = view.views[0].camera.global_basis
				var source_error := _basis_error(actual_basis, draw.basisFloat32Bits)
				var quaternion_basis := SourceQuaternion.basis(SourceQuaternion.axis_angle(Vector3.UP, yaw))
				var quaternion_error := _basis_error(quaternion_basis, draw.basisFloat32Bits)
				reference_camera.global_transform = Transform3D(Basis(Vector3.UP, yaw), expected)
				var old_basis := reference_camera.global_basis
				var captured_basis := _basis_from_bits(draw.basisFloat32Bits)
				var input_error := _basis_error(captured_basis, draw.basisFloat32Bits)
				reference_camera.global_transform = Transform3D(captured_basis, expected)
				var source_stored_error := _basis_error(reference_camera.global_basis, draw.basisFloat32Bits)
				var global_stored_bits := _basis_bits(reference_camera.global_basis)
				reference_camera.transform = Transform3D(captured_basis, expected)
				var local_stored_error := _basis_error(reference_camera.global_basis, draw.basisFloat32Bits)
				var local_value_error := _basis_error(reference_camera.transform.basis, draw.basisFloat32Bits)
				var source_render_transform := reference_camera.get_camera_transform()
				var actual_render_transform: Transform3D = view.views[0].camera.get_camera_transform()
				# RenderingServer orthonormalizes once more before the GLES3 affine inverse.
				var server_transform := actual_render_transform.orthonormalized()
				var server_error := _basis_error(server_transform.basis, draw.basisFloat32Bits)
				var server_inverse := server_transform.affine_inverse()
				var inverse_error := _basis_error(server_inverse.basis, draw.inverseBasisFloat32Bits)
				var inverse_position_error := _vector_error(server_inverse.origin, draw.inversePositionFloat32Bits)
				reference_camera.set_disable_scale(false)
				reference_camera.transform = Transform3D(captured_basis, expected)
				var scale_enabled_global_error := _basis_error(reference_camera.global_basis, draw.basisFloat32Bits)
				var scale_enabled_render_error := _basis_error(reference_camera.get_camera_transform().basis, draw.basisFloat32Bits)
				reference_camera.set_disable_scale(true)
				var native_sine := _double_bits(sin(yaw / 2))
				var native_cosine := _double_bits(cos(yaw / 2))
				orientation_report.append({"decoy": sample.decoy, "yawBits": sample.yawBits,
					"sourceBasisBits": draw.basisFloat32Bits, "nativeBasisBits": _basis_bits(actual_basis),
					"oldBasisBits": _basis_bits(old_basis), "nativeError": source_error, "sourceInputError": input_error,
					"sourceStoredError": source_stored_error, "sourceStoredBits": global_stored_bits,
					"sourceLocalStoredError": local_stored_error, "sourceLocalValueError": local_value_error,
					"sourceRenderBasisBits": _basis_bits(source_render_transform.basis),
					"sourceRenderError": _basis_error(source_render_transform.basis, draw.basisFloat32Bits),
					"scaleEnabledGlobalError": scale_enabled_global_error, "scaleEnabledRenderError": scale_enabled_render_error,
					"sourceInverseBasisBits": draw.inverseBasisFloat32Bits,
					"nativeCameraInverseBasisBits": _basis_bits(actual_render_transform.affine_inverse().basis),
					"nativeServerBasisBits": _basis_bits(server_transform.basis), "nativeServerError": server_error,
					"nativeInverseBasisBits": _basis_bits(server_inverse.basis),
					"sourceInversePositionBits": draw.inversePositionFloat32Bits,
					"nativeInversePositionBits": _float32_bits([server_inverse.origin.x, server_inverse.origin.y, server_inverse.origin.z]),
					"nativeInversePositionError": inverse_position_error,
					"sourceRenderInverseError": _basis_error(source_render_transform.affine_inverse().basis, draw.inverseBasisFloat32Bits),
					"nativeInverseError": inverse_error,
					"oldError": _basis_error(old_basis, draw.basisFloat32Bits), "quaternionMatches": quaternion_matches,
					"sourceSineBits": draw.quaternionBits[1], "sourceCosineBits": draw.quaternionBits[3],
					"nativeSineBits": native_sine, "nativeCosineBits": native_cosine})
				if source_error > 0:
					print("PIP_ORIENTATION_WITNESS yaw=", sample.yaw, " native=", source_error, " quaternion=", quaternion_error)
				if native_sine != str(draw.quaternionBits[1]) or native_cosine != str(draw.quaternionBits[3]):
					print("PIP_ORIENTATION_TRIG_WITNESS yaw=", sample.yaw)
				_check(source_error == 0, "PiP camera global basis matches the original Float32 basis")
				_check(server_error == 0, "PiP renderer basis matches the original Float32 basis")
				_check(inverse_error == 0, "PiP renderer inverse basis matches the original Float32 view matrix")
				_check(inverse_position_error == 0, "PiP renderer inverse position matches the original Float32 view matrix")
	_check(large_bases.size() == 2 and large_bases[0] != large_bases[1],
		"Distinct source headings survive when their angles share one Float32 representation")
	if orientation_gate:
		var report := FileAccess.open("res://artifacts/terra/pip-orientation-report.json", FileAccess.WRITE)
		_check(report != null, "Retain exact PiP orientation and trigonometry witnesses")
		if report != null:
			report.store_string(JSON.stringify(orientation_report, "  "))
			report.close()
	view.free()
	stage.free()
	Controls.power_pref = previous_power

func _basis_error(basis: Basis, bits: Array) -> float:
	var values := [basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z]
	return _float32_error(values, bits)

func _vector_error(vector: Vector3, bits: Array) -> float:
	return _float32_error([vector.x, vector.y, vector.z], bits)

func _float32_error(values: Array, bits: Array) -> float:
	var maximum := 0.0
	for index in values.size():
		maximum = maxf(maximum, absf(float(values[index]) - str(bits[index]).hex_decode().decode_float(0)))
	return maximum

func _basis_from_bits(bits: Array) -> Basis:
	return Basis(Vector3(str(bits[0]).hex_decode().decode_float(0), str(bits[1]).hex_decode().decode_float(0), str(bits[2]).hex_decode().decode_float(0)),
		Vector3(str(bits[3]).hex_decode().decode_float(0), str(bits[4]).hex_decode().decode_float(0), str(bits[5]).hex_decode().decode_float(0)),
		Vector3(str(bits[6]).hex_decode().decode_float(0), str(bits[7]).hex_decode().decode_float(0), str(bits[8]).hex_decode().decode_float(0)))

func _double_bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _basis_bits(basis: Basis) -> Array:
	return _float32_bits([basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z])

func _float32_bits(values: Array) -> Array:
	var result: Array = []
	for value: float in values:
		var bytes := PackedByteArray()
		bytes.resize(4)
		bytes.encode_float(0, value)
		result.append(bytes.hex_encode())
	return result

func _finish_pose() -> void:
	print("PIP_ORIENTATION" if orientation_gate else "PIP_POSE", " assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
