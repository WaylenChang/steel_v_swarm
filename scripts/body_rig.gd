class_name BodyRig
extends Node3D

var source_root: Node3D
var profile: Dictionary = {}
var nodes: Dictionary = {}
var materials: Array = []
var forms: Dictionary = {}
var mounts: Dictionary = {}
var npc_muzzle_index := -1
var objects: Array = []
var scratch_nodes: Array[Node3D] = []
var morph: Dictionary = {}
var form := "ground"
var visual_random := RandomNumberGenerator.new()
var poses := BodyPose.new()
var motion := BodyMotionState.new()

static func available(key: String) -> bool:
	return not key.is_empty() and Content.balance.get("bodies", {}).has(key) and ResourceLoader.exists("res://assets/bodies/%s.scn" % key)

static func entity_key(side: String, kind: String) -> String:
	var key: String = Content.balance.get("bodyRules", {}).get("entityKeys", {}).get(kind, "")
	return side.to_lower() + "_" + key if not key.is_empty() else ""

func configure(key: String, phase: Callable = Callable()) -> bool:
	if source_root != null:
		push_error("Body rig must be configured only once")
		return false
	var path := "res://assets/bodies/%s.scn" % key
	if not available(key):
		push_error("Missing original body scene; regenerate and pack body content: " + path)
		return false
	profile = Content.balance.bodies[key]
	source_root = (load(path) as PackedScene).instantiate()
	add_child(source_root)
	_collect(source_root)
	poses.configure(nodes)
	for spec: Dictionary in profile.get("scratch", []):
		var node := Node3D.new()
		node.rotation_order = SourceEuler.ORDERS.find_key(spec.order)
		node.transform = Transform3D(SourceQuaternion.basis(BodyPose.quaternion(spec.q)).scaled_local(BodyPose.vector(spec.s)), BodyPose.vector(spec.p))
		node.set_meta("source_trs", spec)
		add_child(node)
		scratch_nodes.append(node)
		poses.register(node)
	materials = source_root.get_meta("source_materials")
	visual_random.randomize()
	for index in range(materials.size()):
		if materials[index] is ShaderMaterial:
			var sample: float = phase.call(index) if phase.is_valid() else float(visual_random.randi()) / 4294967296.0
			materials[index].set_shader_parameter("uTime", sample * float(Content.balance.bodyRules.shield.timeWindow))
	# Allocate before filling: emitter entries and morph shield state share identity.
	for spec: Dictionary in profile.objects:
		objects.append([] if spec.type == "array" else {})
	for index in range(profile.objects.size()):
		var spec: Dictionary = profile.objects[index]
		if spec.type == "array":
			for item: Variant in spec.value:
				objects[index].append(_decode(item))
		elif spec.type == "map":
			for item: Array in spec.value:
				objects[index][_decode(item[0])] = _decode(item[1])
		elif spec.type == "set":
			for item: Variant in spec.value:
				objects[index][_decode(item)] = true
		else:
			for name: String in spec.value:
				objects[index][name] = _decode(spec.value[name])
	forms = _decode(profile.forms)
	mounts = _decode(profile.mounts)
	if mounts.get("guns") != null:
		# The source battery is a separate scene root outside body registration.
		mounts.guns.set_meta("source_detached_view", true)
	for name: String in profile.shieldMaterials:
		forms[name].shield.material = materials[int(profile.shieldMaterials[name])]
	if profile.morph != null:
		morph = _decode(profile.morph)
		morph.gg = nodes[int(profile.morph.gg)]
		morph.ag = nodes[int(profile.morph.ag)]
		morph.ground = forms.ground
		morph.air = forms.air
		if forms.ground.get("shield") != null and forms.air.get("shield") != null:
			forms.air.shield.state = forms.ground.shield.state
	return true

func _collect(node: Node3D) -> void:
	var id := int(String(node.name).trim_prefix("n_"))
	nodes[id] = node
	node.set_meta("source_id", id)
	for child: Node3D in node.get_children():
		_collect(child)

func _decode(value: Variant) -> Variant:
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_decode(item))
		return result
	if not value is Dictionary:
		return value
	if value.has("$node"):
		return nodes[int(value["$node"])]
	if value.has("$scratch"):
		return scratch_nodes[int(value["$scratch"])]
	if value.has("$ref"):
		return objects[int(value["$ref"])]
	if value.has("$material"):
		return materials[int(value["$material"])]
	if value.has("$number"):
		return {"-Infinity": -INF, "Infinity": INF, "NaN": NAN}[value["$number"]]
	if value.has("$vector2"):
		return Vector2(value["$vector2"][0], value["$vector2"][1])
	if value.has("$vector3"):
		return Vector3(value["$vector3"][0], value["$vector3"][1], value["$vector3"][2])
	if value.has("$quaternion"):
		var q: Array = value["$quaternion"]
		return Quaternion(q[0], q[1], q[2], q[3])
	if value.has("$euler"):
		return {"angles": Vector3(value["$euler"][0], value["$euler"][1], value["$euler"][2]), "order": value["$euler"][3]}
	if value.has("$matrix4"):
		var matrix: Array = value["$matrix4"]
		return Transform3D(Basis(Vector3(matrix[0], matrix[1], matrix[2]), Vector3(matrix[4], matrix[5], matrix[6]), Vector3(matrix[8], matrix[9], matrix[10])),
			Vector3(matrix[12], matrix[13], matrix[14]))
	if value.has("$color"):
		return Color(value["$color"][0], value["$color"][1], value["$color"][2])
	var result: Dictionary = {}
	if value.has("$map"):
		for entry: Array in value["$map"]:
			result[_decode(entry[0])] = _decode(entry[1])
	elif value.has("$set"):
		for entry: Variant in value["$set"]:
			result[_decode(entry)] = true
	else:
		for key: String in value:
			result[key] = _decode(value[key])
	return result

func fire(event: Dictionary) -> Dictionary:
	var time: Variant = event.get("t0")
	if not (time is float or time is int) or not is_finite(float(time)):
		return {}
	var selected: Variant = event.get("slot")
	if not ControlPreferences.truthy(selected):
		selected = "light"
	if not selected is String:
		return {}
	var active: Dictionary = {}
	for name: String in forms:
		var entry := _fire_owner(forms[name], event, selected)
		if name == form:
			active = entry
	return active

func fire_npc(now: float, gun: int = 0) -> Node3D:
	var muzzles: Array = mounts.get("muzzles", [])
	var battery: Array = mounts.get("gunMuzzles", [])
	var battery_port: Node3D = battery[gun] if gun >= 0 and gun < battery.size() else null
	var owner: Dictionary = forms.get(form, {})
	var light: Node3D = owner.get("muzzles", {}).get("light", {}).get("n")
	var port: Node3D
	if is_visible_in_tree():
		if not muzzles.is_empty():
			npc_muzzle_index = posmod(npc_muzzle_index + 1, muzzles.size())
			port = muzzles[npc_muzzle_index]
		else:
			port = mounts.muzzle if mounts.get("muzzle") != null else battery_port if not battery.is_empty() else light
	var recoil_port: Node3D = battery_port if not battery.is_empty() else muzzles[npc_muzzle_index] if npc_muzzle_index >= 0 else light
	BodyCombatFx.fire_unit_motion(owner, recoil_port, now)
	return port

func _fire_owner(owner: Dictionary, event: Dictionary, slot: String) -> Dictionary:
	if not owner.get("weaponSequences", {}).has(slot):
		return {}
	var sequence: Dictionary = owner.weaponSequences[slot]
	if sequence.has("event") and is_same(sequence.event, event):
		return sequence.entries[int(sequence.index)]
	sequence.event = event
	sequence.index = posmod(int(sequence.index) + 1, sequence.entries.size())
	var active: Dictionary = sequence.entries[int(sequence.index)]
	active.firedAt = float(event.t0)
	if active.get("payload") != null:
		poses.set_scale(active.payload, Vector3.ONE * float(Content.balance.bodyRules.payloadScale))
	owner.wpn[slot].ref = active.ref
	owner.wpn[slot].muz = active.muzzle
	owner.muzzles[slot].n = sequence.entries[posmod(int(sequence.index) + 1, sequence.entries.size())].muzzle
	var alternating: Variant = owner.get("alternating")
	if alternating is Dictionary and alternating.get("slot") == slot:
		alternating.index = sequence.index
	var emitter_names: Dictionary = {}
	for entry: Dictionary in sequence.entries:
		emitter_names[str(entry.muzzle.get_meta("source_name"))] = true
	for joint: Array in owner.get("combat", {}).get("joints", []):
		if emitter_names.has(joint[1]):
			var node: Node3D = owner.combat.nodes[joint[0]]
			if node.get_parent() != active.muzzle:
				node.reparent(active.muzzle, false)
	var flames: Variant = owner.get("flames")
	if flames is Dictionary:
		for flame: Node3D in flames.get(slot, []):
			if flame.get_parent() != active.muzzle:
				flame.reparent(active.muzzle, false)
	var hair: Variant = owner.get("hairFlick")
	if slot == "light" and hair != null:
		if float(event.t0) - float(hair.firedAt) > float(hair.burstGap):
			hair.startedAt = float(event.t0)
		hair.firedAt = float(event.t0)
	return active

func pose_payloads(now: float, selected_form: String = "") -> void:
	var owners: Array = forms.values() if selected_form.is_empty() else [forms[selected_form]]
	for owner: Dictionary in owners:
		for slot: String in owner.get("weaponSequences", {}):
			var duration: float = owner.get("combat", {}).get("clips", {}).get(slot, {}).get("duration", Content.balance.bodyRules.payloadDuration)
			if duration == 0:
				duration = float(Content.balance.bodyRules.payloadDuration)
			for entry: Dictionary in owner.weaponSequences[slot].entries:
				if entry.get("payload") == null:
					continue
				var age := now - float(entry.firedAt)
				poses.set_scale(entry.payload, Vector3.ONE * (float(Content.balance.bodyRules.payloadScale) if age >= 0 and age < duration else 1.0))

func step_morph(delta: float, altitude: float) -> void:
	BodyMorph.swap(self, delta, altitude)

func step_combat(entity: Dictionary, now: float, delta: float) -> void:
	BodyCombatFx.step(self, entity, now, delta)

func step_locomotion(entity: Dictionary, delta: float, now: float, previous: Vector3, previous_yaw: float, frame: Dictionary = {}) -> void:
	BodyLocomotion.step(self, entity, delta, now, previous, previous_yaw, frame)

func begin_motion(source_entity: String) -> void:
	motion.configure(source_entity)

func sample_motion(delta: float, position: Vector3, yaw: float, previous: Vector3, previous_yaw: float) -> bool:
	return motion.advance(position, yaw, previous, previous_yaw, delta)

func pose_biped_motion(delta: float, now: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing a biped")
	BodyGaitBiped.step(poses, motion.values, forms[form], delta, now, motion.kinematics.speed, motion.kinematics.yaw_rate)

func pose_aerial_motion(delta: float, now: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing an aerial rig")
	BodyGaitAerial.step(poses, motion.values, forms[form], delta, now, motion.kinematics.forward, motion.kinematics.lateral, motion.kinematics.yaw_rate)

func pose_quad_motion(delta: float, now: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing a quad rig")
	BodyGaitQuad.step(poses, motion.values, forms[form], delta, now, motion.kinematics.speed, motion.kinematics.yaw_rate)

func pose_vehicle_motion(delta: float, now: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing a vehicle rig")
	BodyGaitVehicle.step(poses, motion.values, forms[form], delta, now, motion.kinematics.speed, motion.kinematics.forward, motion.kinematics.yaw_rate)

func pose_jump(entity: Dictionary, delta: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing a jump")
	BodyJumpPose.step(poses, motion.values, forms[form], entity, delta)

func pose_cast(entity: Dictionary, now: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing a cast")
	BodyCastPose.step(poses, motion.values, forms[form], entity, now)

func pose_species(delta: float, now: float) -> void:
	assert(not motion.values.is_empty(), "Sample body displacement before posing species overlays")
	BodySpeciesPose.step(poses, motion.values, forms[form], delta, now, motion.kinematics.speed)

func stabilize_pose() -> void:
	BodyAimPose.stabilize(poses, forms[form])

func aim_forward(selected_form: String = "", shared_state: Variant = null) -> void:
	BodyAimPose.forward(poses, forms[form if selected_form.is_empty() else selected_form], shared_state)

func reset_anatomical() -> void:
	for owner: Dictionary in forms.values():
		BodyAnatomicalPose.reset(poses, owner)

func pose_anatomical(blend: float = 1.0, selected_form: String = "") -> void:
	BodyAnatomicalPose.step(poses, forms[form if selected_form.is_empty() else selected_form], blend)

func pose_hair(now: float) -> void:
	for owner: Dictionary in forms.values():
		BodyAnatomicalPose.hair(poses, owner, now)

func pose_equipment(selected_form: String = "", shared_state: Variant = null) -> void:
	BodyEquipmentPose.step(poses, forms[form if selected_form.is_empty() else selected_form], shared_state)

func pose_archery() -> void:
	BodyArcheryPose.step(poses, forms[form])

func pose_reference(entity: Dictionary, delta: float, now: float, apply_shield: bool = true) -> void:
	BodyReferenceMotion.step(poses, forms[form], entity, delta, now, apply_shield)

func clear_morph_shields() -> void:
	for owner: Dictionary in forms.values():
		BodyReferenceMotion.clear_shield(poses, owner)

func flash_shield(strength: float) -> void:
	var index: Variant = profile.get("hitShieldMaterial")
	if index != null and materials[int(index)] is ShaderMaterial:
		ShieldPresentation.hit(materials[int(index)], strength)

func finish_motion(altitude: float, flying: bool) -> Dictionary:
	if motion.values.is_empty():
		return {}
	var owner: Dictionary = forms[form]
	motion.values.w = BodyMotionState.weights(motion.values, owner, {"groundY": Content.constants.MORPH.GROUND_Y,
		"y": altitude, "flies": flying, "top": owner.get("top")})
	return motion.values.w

func pose_morph() -> void:
	BodyMorph.pose(self)

func next_muzzle(slot: String, selected_form: String = "") -> Vector3:
	var owner: Dictionary = forms.get(selected_form if not selected_form.is_empty() else form, {})
	var marker: Dictionary = owner.get("muzzles", {}).get(slot, {})
	var node: Node3D = marker.get("n")
	return node.global_position if is_instance_valid(node) and not marker.get("fxOnly", false) else Vector3(NAN, NAN, NAN)

func ring_height(base: float) -> float:
	for child: Node3D in source_root.get_children():
		if child.get_meta("teamRing", false):
			return base + poses.position_axis(child, "y")
	return NAN

func spin(delta: float) -> void:
	if not is_finite(delta) or delta <= 0:
		return
	for spinner: Dictionary in profile.spin:
		var node: Node3D = nodes[int(spinner.node)]
		var angles := poses.rotation(node)
		angles[WeaponPresentation.axis_index(spinner.axis)] += delta * float(spinner.rate)
		poses.set_rotation(node, angles)
