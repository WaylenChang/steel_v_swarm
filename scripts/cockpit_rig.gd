class_name CockpitRig
extends Node3D

signal echo_fired(definition: Dictionary, origin: Vector3)

var source_root: Node3D
var character: String
var profile: Dictionary
var nodes: Dictionary = {}
var gun: Node3D
var ground: Node3D
var air: Node3D
var flash: Node3D
var cock_ground: Node3D
var cock_air: Node3D
var kick := 0.0
var control: Dictionary = {}
var weapons := WeaponPresentation.new()
var bursts := BurstPresentationQueue.new()
var accepted_serial := -1
var flash_ttl := 0.0
var flash_heavy := false
var flash_rng := RandomNumberGenerator.new()
var muzzle_cache: Dictionary = {}
var current_cache := 0
var authority_pose: Dictionary = {}
var client_weapons: ClientWeaponDefinitions

func configure(pilot: String) -> void:
	character = pilot
	profile = Content.balance.cockpit[character]
	weapons.configure(profile)
	for i in range(profile.muzzleCache.points.size()):
		var point: Array = profile.muzzleCache.points[i]
		muzzle_cache[i] = Vector3(point[0], point[1], point[2])
	current_cache = int(profile.muzzleCache.current)
	flash_rng.randomize()
	source_root = (load("res://assets/cockpits/%s.scn" % character) as PackedScene).instantiate()
	add_child(source_root)
	_collect(source_root)
	gun = nodes[int(profile.nodes.gun)]
	ground = nodes.get(int(profile.nodes.ground))
	air = nodes.get(int(profile.nodes.air))
	flash = nodes[int(profile.nodes.flash)]
	cock_ground = nodes.get(int(profile.nodes.cockGround))
	cock_air = nodes.get(int(profile.nodes.cockAir))
	flash.visible = false
	if not SourceOutlineBinding.install(source_root):
		source_root.hide()

func _collect(node: Node3D) -> void:
	if node.get_meta("source_outline_helper", false):
		return
	nodes[int(String(node.name).trim_prefix("n_"))] = node
	for child: Node3D in node.get_children():
		_collect(child)

func sync_visibility(aiming: bool, fov: float, base_fov: float, flying: bool) -> void:
	var hide: bool = aiming or (base_fov > 0 and fov < base_fov - Content.balance.cockpitRules.FOV_EPS)
	if cock_air != null:
		cock_air.visible = not hide and flying
		cock_ground.visible = not hide and not flying
	if ground != null:
		ground.visible = not hide and not flying
		air.visible = not hide and flying
	for child: Node3D in source_root.get_children():
		if child not in [gun, cock_air, cock_ground]:
			child.visible = not hide
	for child: Node3D in gun.get_children():
		if child not in [flash, ground, air]:
			child.visible = not hide

func update_view(unit: BattleUnit, slot: String, aiming: bool, delta: float, simulation_clock: float, view_mode: String = "fpv") -> void:
	if source_root == null:
		return
	unit.render_view_mode = view_mode
	visible = unit.alive()
	for echo: Dictionary in bursts.take_due(simulation_clock):
		if not unit.alive():
			continue
		var fired_slot: String = echo.payload.slot
		var form := "air" if unit.flying and profile.motion.has("air") else "ground"
		var sequence: Dictionary = weapons.sequences[form][fired_slot]
		var index := posmod(int(sequence.index) + 1, sequence.times.size())
		var id := int(profile.emissions[form][fired_slot][index])
		if id >= 0:
			muzzle_cache[current_cache] = gun.to_local(nodes[id].global_position)
		var origin := gun.to_global(muzzle_cache[current_cache])
		if view_mode == "tps":
			var heading := unit.body_presentation.previous_yaw - PI if unit.body_presentation != null else unit.facing_yaw()
			origin = BodyLaunchPose.resolve(unit.body, fired_slot, unit.global_position, unit.view_eye_height(), heading,
				unit.camera.global_position, TargetingMath.maximum_range(echo.payload.definition)).origin
		if unit.body_presentation != null:
			var simulation: BattleSimulation = unit.get_parent()
			unit.body_presentation.fire_local(fired_slot, simulation.presentation_time())
		_mark_fire(weapons.last_serial + 1, fired_slot, simulation_clock)
		echo_fired.emit(echo.payload.definition, origin)
	weapons.advance(delta, simulation_clock)
	apply_mirrors(unit.flying, simulation_clock)
	sync_visibility(aiming, unit.camera.fov, Content.constants.UNITS[unit.kind].fov, unit.flying)
	kick = maxf(0, kick - delta * Content.balance.cockpitRules.kickDecay)
	if not authority_pose.is_empty() and authority_pose.get("visual_serial", authority_pose.serial) == weapons.last_serial and authority_pose.slot == slot and authority_pose.clock <= simulation_clock:
		kick = maxf(0, authority_pose.kick - (simulation_clock - authority_pose.clock) * Content.balance.cockpitRules.kickDecay)
	var level := unit.combat_level(slot)
	var definition := client_weapons.own_weapon(unit.character, slot, unit.combat_level("light"), unit.combat_level("heavy")) if client_weapons != null else Content.local_weapon(unit.character, slot, level)
	var reload := Vector3.ZERO
	if unit.reload_at.has(slot):
		var progress := 1 - maxf(0, float(unit.reload_at[slot]) - simulation_clock) / maxf(0.001, definition.reload)
		reload = CockpitPose.reload_offset(definition, progress)
	var elevation: float = control.get("elevation", 0) if aiming and slot == "heavy" else 0.0
	gun.transform = CockpitPose.transform_for(profile, reload, elevation, kick)
	sync_emitter(slot, unit.flying)
	step_flash(delta)

func sync_authority_pose(state: Dictionary) -> void:
	if state.is_empty():
		authority_pose = {}
		return
	if not is_finite(state.clock) or not is_finite(state.kick) or state.slot not in ["light", "heavy"]:
		return
	if not authority_pose.is_empty() and state.clock < authority_pose.clock:
		return
	authority_pose = state.duplicate()

func fire_feedback(event: Dictionary) -> void:
	if int(event.serial) <= accepted_serial:
		return
	if _mark_fire(maxi(int(event.serial), weapons.last_serial + 1), event.slot, event.clock):
		accepted_serial = int(event.serial)
		if event.has("level"):
			var definition: Dictionary = client_weapons.own[event.slot] if client_weapons != null and client_weapons.own.has(event.slot) else Content.local_weapon(character, event.slot, float(event.level))
			bursts.schedule(definition, event.clock, {"slot": event.slot, "definition": definition})

func _mark_fire(serial: int, slot: String, at: float) -> bool:
	if weapons.fire(serial, slot, at):
		kick = 1
		flash.visible = true
		flash_ttl = Content.balance.cockpitRules.flash.duration
		flash_heavy = slot == "heavy"
		return true
	return false

func sync_emitter(slot: String, flying: bool) -> void:
	var form := "air" if flying and profile.motion.has("air") else "ground"
	var index := maxi(0, int(weapons.sequences[form][slot].index))
	var id := int(profile.emissions[form][slot][index])
	if id >= 0:
		# Source _muzzle.copy() mutates whichever fallback vector the previous slot selected.
		muzzle_cache[current_cache] = gun.to_local(nodes[id].global_position)
	else:
		var set: Dictionary = profile.muzzleCache.forms[form]
		current_cache = int(set.get(slot, set.get("light", set.get("heavy"))))
	flash.position = muzzle_cache[current_cache]

func step_flash(delta: float, sample: float = NAN) -> void:
	if flash_ttl <= 0:
		return
	flash_ttl = maxf(0, flash_ttl - delta)
	if flash_ttl <= 0:
		flash.visible = false
		return
	var style: Dictionary = Content.balance.cockpitRules.flash
	var value := sample if is_finite(sample) else flash_rng.randf()
	flash.scale = Vector3.ONE * (style.minimum + value * style.span) * (style.heavy if flash_heavy else 1.0)

func apply_mirrors(flying: bool, now: float) -> void:
	var form := "air" if flying and profile.motion.has("air") else "ground"
	var poses := weapons.pose(form, now)
	for binding: Dictionary in profile.bindings:
		var target: Node3D = nodes[int(binding.target)]
		var spec: Dictionary = poses[binding.source]
		target.scale = Vector3(spec.scale[0], spec.scale[1], spec.scale[2])
		if binding.rotate:
			target.quaternion = WeaponPresentation.source_rotation(spec)
		if binding.translate and target.get_parent().get_meta("source_name", "") == spec.parent:
			target.position = Vector3(spec.position[0], spec.position[1], spec.position[2])

# Initial-geometry fixture accessor; live fallback aliases are tracked by sync_emitter.
func muzzle_position(slot: String, index: int, flying: bool) -> Vector3:
	var form := "air" if profile.emissions.has("air") and flying else "ground"
	var ids: Array = profile.emissions[form][slot]
	var port_index := posmod(index, ids.size())
	var id := int(ids[port_index])
	if id >= 0:
		return nodes[id].global_position
	# Some source slots have no cloned emitter; retain their measured gun-local fallback.
	var point: Array = profile.forms[form][slot][port_index]
	return gun.to_global(Vector3(point[0], point[1], point[2]))
