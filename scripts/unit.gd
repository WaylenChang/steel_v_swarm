class_name BattleUnit
extends CharacterBody3D

var entity_id: int
var peer_id: int = 0
var side: String
var kind: String
var character: String = ""
var special: Dictionary = {}
var clone_ids: Array[int] = []
var clones_initialized := false
var last_hit_target := 0
var carrier_ids: Array[int] = []
var creep_multiplier := 1.0
var npc_cached_target := 0
var npc_cache_phase := -1
var npc_cached_tick := -1
var npc_wave := 0
var npc_has_wave := false
var npc_progress := 0.0
var npc_engaged := false
var npc_cooldown := 0.0
var geometry_override: Dictionary = {}
var lane: int = 0
var has_lane := false
var spawn_slot: int = 0
var is_bot := false
var hp := 0.0
var max_hp := 0.0
var shield := 0.0
var max_shield := 0.0
var power := 0.0
var max_power := 0.0
var armor := 0.0
var money := 0.0
var score := 0.0
var deaths := 0
var radius := 1.0
var effect_radius := 0.0
var height := 2.0
var speed := 0.0
var flying := false
var yaw := 0.0
var pitch := 0.0
var input_state: Dictionary = {}
var upgrades: Dictionary = {"lw": 0, "hw": 0, "def": 0, "atk": 0, "hp": 0, "ar": 0, "sp": 0, "ch": 0}
var ammo: Dictionary = {}
var reload_at: Dictionary = {}
var fire_at: Dictionary = {}
var fire_serial := 0
var cooldowns: Dictionary = {}
var buffs: Array = []
var status: Dictionary = {}
var cast_state: Dictionary = {}
var ability_charges: Dictionary = {}
var defending := false
var last_fired_at: Dictionary = {}
var assists: Dictionary = {}
var damage_out := 0.0
var threat: Dictionary = {}
var bleed: Dictionary = {}
var heal_aura: Dictionary = {}
var wet := 0
var fluid_environment: Dictionary = {}
var impulse_velocity := Vector2.ZERO
var charge := 0.0
var low_gravity := false
var lift := -1.0
var jump_was_held := false
var air_sink := 0.0
var air_sink_speed := 0.0
var lift_lock_until := 0.0
var damaged_at := -100.0
var respawn_at := 0.0
var target_position := Vector3.ZERO
var target_yaw := 0.0
var model: Node3D
var camera: Camera3D
var cockpit: CockpitRig
var weapon_pose: AuthorityWeaponPose
var animation_player: AnimationPlayer
var path_follower: PathFollow3D
var reaction_at := 0.0
var bot_target := 0
var aim_anchor := 0
var lock_target := 0
var lock_at := -100.0
var lock_check_at := 0.0
var lock_keep_index := 0
var aim_off_at := -100.0
var gun_cooldowns: Array[float] = []
var animation_until := 0.0
var movement_shape: CollisionShape3D
var hit_area: Area3D
var presentation_visible := true
var view_offset := Vector3.ZERO
var view_offset_ready := false
var camera_cache_frame := -1
var camera_cache_signature: Array = []
var camera_cache_origin := Vector3.ZERO

func configure(info: Dictionary) -> void:
	entity_id = int(info.id)
	peer_id = int(info.get("peer", 0))
	side = info.side
	kind = info.kind
	character = info.get("character", "")
	special = info.get("special", {}).duplicate(true)
	lane = int(info.get("lane", 0))
	has_lane = bool(info.get("has_lane", info.has("lane")))
	spawn_slot = int(info.get("spawn_slot", 0))
	is_bot = info.get("bot", false)
	effect_radius = float(info.get("effect_radius", 0))
	creep_multiplier = float(info.get("creep_multiplier", 1))
	if not Content.constants.UNITS.has(kind) and not (kind == "slab" and special.get("role") == "slab") and not (kind == "decoy_beacon" and special.get("role") == "hologram") and not (kind == "kami" and special.get("role") == "carrier") and not (special.get("role") == "hazard" and (Content.constants.HAZARDS.has(kind) or kind in ["aasite", "relay"])):
		push_error("Unsupported authority entity kind: " + kind)
		return
	var unit: Dictionary = Content.constants.UNITS.get(kind, {})
	if special.get("role") == "civilian":
		var body := CivilianRules.body(entity_id)
		radius = float(Content.constants.TARGET_R.civ) * float(body.radiusScale)
		height = float(Content.constants.TARGET_H.civ) * float(body.heightScale)
		max_hp = float(Content.constants.UNITS.civilian.hp)
		armor = float(Content.constants.UNITS.civilian.armor)
		speed = CivilianRules.speed(special.get("spy", false))
	elif special.get("role") == "hazard":
		radius = Content.balance.hazard_volumes[kind].radius
		height = Content.balance.hazard_volumes[kind].height
		max_hp = special.hp
		armor = special.armor
	elif special.get("role") == "carrier":
		var profile: Dictionary = Content.balance.companions[special.model_key]
		radius = profile.radius
		height = profile.height
		max_hp = float(special.hp)
	elif kind == "slab":
		var soldier_height: float = Content.constants.TARGET_H["creep:soldier"]
		radius = soldier_height * 0.5
		height = soldier_height * 1.6
		max_hp = float(special.hp)
	elif kind == "decoy_beacon":
		radius = Content.balance.companions[side.to_lower() + "_" + kind].radius
		height = Content.balance.companions[side.to_lower() + "_" + kind].height
		max_hp = 120
		speed = 18
	elif not character.is_empty():
		var hero: Dictionary = Content.heroes[character]
		radius = hero.radius
		height = hero.height
		armor = hero.armor
		speed = hero.speed
		max_hp = round(unit.hp * hero.mods.get("hp", 1))
		max_shield = round(unit.get("shield", 0) * hero.mods.get("sp", 1))
		max_power = round(unit.get("mp", 0) * hero.mods.get("mp", 1))
		lift = Content.constants.FLIGHT.LIFT_MAX
		money = Content.constants.ECON.START
	else:
		radius = Content.balance.unitVolumes[kind][side].radius
		height = Content.balance.unitVolumes[kind][side].height
		armor = unit.get("armor", 0)
		speed = unit.get("speed", 0)
		max_hp = unit.hp
	hp = max_hp
	shield = max_shield
	power = max_power
	if special.get("role") in ["clone", "summon"]:
		for property: String in ["hp", "max_hp", "shield", "max_shield", "armor", "speed"]:
			if special.has(property):
				set(property, float(special[property]))
	if special.get("role") == "clone":
		money = 0
		power = 0
		max_power = 0
	flying = special.get("role") == "carrier" or bool(unit.get("fly", false)) or kind in ["drone", "heli"]
	position = info.position
	yaw = float(info.get("yaw", 0))
	rotation.y = yaw
	target_yaw = yaw
	target_position = position
	collision_mask = 1 | 4
	movement_shape = CollisionShape3D.new()
	add_child(movement_shape)
	hit_area = Area3D.new()
	hit_area.collision_layer = 2
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	var hit_shape := CollisionShape3D.new()
	var hit_cylinder := CylinderShape3D.new()
	hit_cylinder.radius = radius
	hit_cylinder.height = height
	hit_shape.shape = hit_cylinder
	hit_shape.position.y = height / 2
	hit_area.add_child(hit_shape)
	if kind == "slab":
		hit_area.remove_child(hit_shape)
		hit_shape.free()
		for size: Vector3 in [Vector3(3.5, 6, 0.4), Vector3(2.2, 4.5, 0.42)]:
			var panel := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			panel.shape = box
			panel.position.y = 3
			panel.rotation.y = PI / 2
			hit_area.add_child(panel)
	add_child(hit_area)
	refresh_collision()
	_build_model()
	if is_pilot():
		camera = Camera3D.new()
		camera.position = CameraPose.anchor(character, Vector3.ZERO, 0, flying)
		camera.fov = unit.get("fov", 68)
		camera.near = Content.balance.cameraRules.near
		camera.far = 3500
		add_child(camera)
		for slot in ["light", "heavy"]:
			ammo[slot] = Content.weapon(character, slot).mag

func _build_model() -> void:
	if special.get("role") in ["third", "civilian"]:
		var key := "%s_%s" % [side.to_lower(), kind] if special.role == "third" else "%s_civilian_%02d" % [String(special.civil_side).to_lower(), int(special.profession)]
		var path := "res://assets/companions/%s.scn" % key
		if not Content.balance.get("companions", {}).has(key) or not ResourceLoader.exists(path):
			push_error("Missing original camp/civilian model; regenerate and pack companion content: " + path)
			return
		model = load(path).instantiate()
		add_child(model)
		model.rotation.y = PI
		var profile: Dictionary = Content.balance.companions[key]
		geometry_override = profile.dimensions.duplicate()
		if special.role == "civilian":
			var body := CivilianRules.body(entity_id)
			var scale_factor := Vector3(float(body.radiusScale) / float(profile.body.radiusScale), float(body.heightScale) / float(profile.body.heightScale), float(body.radiusScale) / float(profile.body.radiusScale))
			model.scale = scale_factor
			for property: String in ["height", "top", "centre"]:
				geometry_override[property] = float(geometry_override[property]) * scale_factor.y
			geometry_override.radius = float(geometry_override.radius) * scale_factor.x
		return
	if special.get("role") == "hazard":
		var file := "res://assets/hazards/%s.scn" % kind
		if not ResourceLoader.exists(file) or not Content.balance.get("hazard_visuals", {}).has(kind):
			push_error("Missing original hazard model: " + file)
			return
		var scene: PackedScene = load(file)
		model = scene.instantiate()
		add_child(model)
		model.rotation_order = EULER_ORDER_XYZ
		model.scale = Vector3.ONE * float(special.scale)
		geometry_override = Content.balance.hazard_visuals[kind].dimensions.duplicate()
		for property: String in ["height", "top", "centre", "radius"]:
			geometry_override[property] = float(geometry_override[property]) * float(special.scale)
		if special.get("collapsed", false):
			apply_collapse(true)
		return
	if special.get("role") in ["summon", "hologram", "carrier"]:
		var model_key: String = special.model_key if special.get("role") == "carrier" else "%s_%s" % [side.to_lower(), kind]
		var file := "res://assets/companions/%s.scn" % model_key
		if not ResourceLoader.exists(file):
			push_error("Missing source companion model: " + file)
			return
		var scene: PackedScene = load(file)
		model = scene.instantiate()
		add_child(model)
		model.rotation.y = PI
		geometry_override = Content.balance.companions[model_key].dimensions if special.get("role") == "carrier" else Content.balance.modelGeometry.units[kind][side]
		return
	if kind == "slab":
		model = Node3D.new()
		add_child(model)
		var bronze := StandardMaterial3D.new()
		bronze.albedo_color = Color.hex(0xd2b77aff)
		var rune := StandardMaterial3D.new()
		rune.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rune.albedo_color = Color.hex(0xffe28aff)
		for index in range(2):
			var panel := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(3.5, 6, 0.4) if index == 0 else Vector3(2.2, 4.5, 0.42)
			panel.mesh = box
			panel.position.y = 3
			panel.rotation.y = PI / 2
			panel.material_override = bronze if index == 0 else rune
			model.add_child(panel)
		geometry_override = {"height": 6.0, "top": 6.0, "centre": 3.0, "radius": 1.75}
		return
	var file := "res://assets/models/reference/%s.glb" % character if not character.is_empty() else "res://assets/models/factions/%s_%s.glb" % [side.to_lower(), kind]
	if ResourceLoader.exists(file):
		var scene: PackedScene = load(file)
		model = scene.instantiate()
		add_child(model)
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		var bounds := AABB()
		var initialized := false
		for mesh in meshes:
			var box: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			bounds = bounds.merge(box) if initialized else box
			initialized = true
		if initialized and bounds.size.y > 0:
			var factor := height / bounds.size.y
			model.scale = Vector3.ONE * factor
			model.position.y = -bounds.position.y * factor
		animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	else:
		model = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(radius * 2, height, radius * 2)
		model.mesh = mesh
		model.position.y = height / 2
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(Content.constants.SIDES[side].color)
		model.material_override = material
		add_child(model)

func is_hero() -> bool:
	return not character.is_empty()

func is_pilot() -> bool:
	return is_hero() and special.get("role") != "clone"

func ensure_weapon_pose() -> void:
	if is_pilot() and (weapon_pose == null or weapon_pose.character != character):
		weapon_pose = AuthorityWeaponPose.new()
		weapon_pose.configure(character)

func ensure_cockpit() -> void:
	if cockpit != null or camera == null:
		return
	cockpit = CockpitRig.new()
	camera.add_child(cockpit)
	cockpit.configure(character)

func alive() -> bool:
	return hp > 0

func has_status(key: String, now: float) -> bool:
	return float(status.get(key, 0)) > now

func eye() -> Vector3:
	return global_position + Vector3.UP * height * Content.constants.SELF_F.eye

func view_eye_height() -> float:
	return CameraPose.eye_height(character, flying, charge) if is_pilot() else height * Content.constants.SELF_F.eye

func view_origin() -> Vector3:
	if not is_pilot():
		return eye()
	var parent := get_parent()
	if parent is BattleSimulation and parent.authoritative:
		return parent.camera_origin(self)
	return global_position + (Basis(Vector3.UP, rotation.y) * view_offset if view_offset_ready else CameraPose.anchor(character, Vector3.ZERO, rotation.y, flying, charge))

func sync_view_camera() -> void:
	if camera != null:
		var parent := get_parent()
		if parent is BattleSimulation and parent.authoritative:
			camera.global_transform = aim_transform()
		else:
			camera.global_position = view_origin()
			camera.rotation = Vector3(pitch, 0, 0)

func visual_dimensions() -> Dictionary:
	if not geometry_override.is_empty():
		return geometry_override
	var geometry: Dictionary = Content.balance.modelGeometry
	return geometry.heroes.get(character, {}) if is_hero() else geometry.units.get(kind, {}).get(side, {})

func aim_point() -> Vector3:
	var dimensions := visual_dimensions()
	if dimensions.is_empty():
		return Vector3(NAN, NAN, NAN)
	# Source acquisition uses the spawn-time measured centre even when the body rotates or morphs.
	return global_position + Vector3.UP * dimensions.centre

func sight_origin() -> Vector3:
	return global_position + Vector3.UP * (Content.constants.LOS.TOWER_EYE_M if kind == "tower" else Content.constants.LOS.EYE_M)

func sight_target() -> Vector3:
	var point := global_position
	if special.get("role") in ["summon", "hologram"]:
		var simulation: BattleSimulation = get_parent()
		point.y = simulation.world.ground_height(point.x, point.z)
	return point + Vector3.UP * (Content.constants.LOS.TOWER_EYE_M if kind in ["base", "tower"] else Content.constants.LOS.TGT_M)

func sight_radius() -> float:
	var reach: float = Content.constants.UNITS.get(kind, {}).get("sight", 0)
	return reach * Content.constants.GAME.AIM_SIGHT_MULT if is_hero() and input_state.get("aim", false) else reach

func refresh_collision() -> void:
	if movement_shape == null or hit_area == null:
		return
	if special.get("role") == "hazard":
		var definition: Dictionary = Content.constants.HAZARDS.get(kind, {})
		collision_layer = 1 if definition.get("block", false) or kind in ["aasite", "relay"] else 0
		hit_area.collision_layer = 2 if alive() and not special.get("collapsed", false) else 0
		var obstacle := CylinderShape3D.new()
		var collapsed := bool(special.get("collapsed", false))
		obstacle.radius = (3.2 if kind == "aasite" else 1.6 if kind == "relay" else float(definition.get("r", 6))) * float(special.scale) * (float(Content.constants.SCENE_STRUCT.RUBBLE_F) if collapsed else 1.0)
		obstacle.height = (3.5 if kind == "aasite" else 8.0 if kind == "relay" else float(definition.get("hgt", 6))) * (0.35 if collapsed else 1.0)
		movement_shape.shape = obstacle
		movement_shape.position.y = obstacle.height / 2
		return
	var active := alive() and not special.get("garrison", false)
	collision_layer = 4 if active and (is_hero() or kind in Content.constants.COLLIDE_KINDS) else 0
	hit_area.collision_layer = 2 if active else 0
	var spec := {"r": radius, "bot": 0.0, "top": height}
	if is_hero():
		spec = Content.heroes[character].colliders["air" if flying else "ground"]
	var cylinder := CylinderShape3D.new()
	cylinder.radius = spec.r
	cylinder.height = spec.top - spec.bot
	movement_shape.shape = cylinder
	movement_shape.position.y = (spec.top + spec.bot) / 2

func aim_direction() -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD

func aim_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), view_origin())

func simulate_movement(delta: float) -> void:
	if not alive() or speed <= 0:
		return
	var motion: Vector2 = input_state.get("move", Vector2.ZERO)
	var simulation: BattleSimulation = get_parent()
	var now := simulation.clock
	var stats: Dictionary = Content.constants.UNITS[kind]
	simulation._update_fluid_state(self)
	var frozen := bool(simulation.weather_dynamics.get("isFrozen", false))
	var terrain_factor := EnvironmentRules.movement_factor(fluid_environment, frozen) * float(simulation._flood_effect(self).slow)
	var standing_surface := simulation._movement_surface(position)
	var held: bool = input_state.get("jump_held", false)
	var previous_position := position
	var slow: float = status.get("slow_factor", 0.6)
	var movement_factor := (slow if slow else 0.6) if has_status("slow_until", now) else 1.0
	if has_status("stun_until", now) or has_status("freeze_until", now):
		movement_factor = 0
	yaw = float(input_state.get("yaw", yaw))
	pitch = float(input_state.get("pitch", pitch))
	if has_status("confuse_until", now):
		yaw += sin(now * 2.7) * 0.5 * delta
	rotation.y = yaw
	if camera != null:
		camera.rotation.x = pitch
		camera.fov = stats.get("zoomFov", 35) if input_state.get("aim", false) else stats.get("fovAir", stats.get("fov", 68)) if flying else stats.get("fov", 68)
	var move_basis := Basis(Vector3.UP, yaw)
	if flying and is_hero():
		move_basis *= Basis(Vector3.RIGHT, pitch)
	var direction := move_basis * Vector3(motion.x, 0, motion.y)
	var weather_direction := direction
	if has_status("confuse_until", now):
		direction.x = -direction.x
		direction.z = -direction.z
	if not flying:
		weather_direction = direction
	var current_speed := speed
	if input_state.get("sprint", false):
		current_speed *= Content.balance.movement.sprint
	if is_hero() and flying:
		current_speed = Content.heroes[character].flySpeed
		if input_state.get("sprint", false):
			current_speed *= Content.balance.movement.sprint
	current_speed *= StatusRules.movement_modifier(buffs, "speed", now) * movement_factor * terrain_factor
	current_speed *= simulation.weather_movement(self, weather_direction, flying or low_gravity or velocity.y > 0 or not is_on_floor(), not flying)
	if has_status("sup_until", now):
		current_speed *= 1 - Content.constants.HIGH_SUP.SPEED * float(status.get("sup_factor", 0))
	if flying:
		if kind == "drone" and held and not jump_was_held:
			var last_shot := maxf(float(last_fired_at.get("light", -INF)), float(last_fired_at.get("heavy", -INF)))
			if now - maxf(last_shot, damaged_at) < Content.constants.IFRAME.COMBAT_S and simulation.request_iframe(self):
				velocity.y += float(stats.vspeed)
		var axis: float = input_state.get("vertical", 0)
		var vertical_speed: float = stats.get("vdown", stats.get("vspeed", current_speed)) if axis < 0 else stats.get("vspeed", current_speed)
		var target := direction * current_speed
		var lift_weather := WeatherRules.air_lift(simulation.weather_dynamics) if axis > 0 else 1.0
		target.y += axis * vertical_speed * movement_factor * terrain_factor * lift_weather
		if is_hero():
			target.y = _step_lift(simulation, target.y, delta)
		velocity = velocity.lerp(target, 1 - exp(-4.0 * delta))
	else:
		air_sink = 0
		var grounded := is_on_floor() or (is_finite(standing_surface) and velocity.y <= 0 and position.y <= standing_surface + Content.constants.AIR.OFF_GROUND)
		if movement_factor <= 0:
			charge = 0
		elif grounded and held and is_hero():
			var seconds: float = Content.constants.MORPH.CHARGE_S if kind == "morph" else Content.constants.CJUMP.CHARGE_S
			charge = minf(1, charge + delta / seconds)
		elif charge > 0 and not held:
			if grounded:
				_launch_charged_jump(simulation)
			else:
				charge = 0
		current_speed *= (1 - 0.6 * charge) * (Content.constants.CJUMP.AIR_SPD_F if low_gravity else 1.0)
		# Source ground velocity is an impulse account, separate from controlled walking.
		if not flying:
			velocity.x = direction.x * current_speed + impulse_velocity.x
			velocity.z = direction.z * current_speed + impulse_velocity.y
			impulse_velocity *= exp(-(0.8 if low_gravity else 6.0) * delta)
			velocity.y -= Content.constants.AIR.GRAV * (Content.constants.CJUMP.GRAV_F if low_gravity else 1.0) * delta
			if input_state.get("jump", false) and not held and grounded and movement_factor > 0 and not low_gravity:
				velocity.y = float(stats.get("jump", 0)) * StatusRules.movement_modifier(buffs, "jump", now) * simulation._terrain_jump_velocity(self) * WeatherRules.jump_velocity(simulation.weather_surface)
			if is_hero():
				_step_lift(simulation, 0, delta)
		input_state["jump"] = false
	move_and_slide()
	if frozen and simulation.world.water_plane(position.x, position.z) != null:
		var ice_surface := simulation._movement_surface(Vector3(position.x, previous_position.y, position.z))
		if is_finite(ice_surface) and position.y < ice_surface:
			position.y = ice_surface
			velocity.y = maxf(0, velocity.y)
	if has_status("rooted_until", now) and status.has("root_position"):
		var root: Vector3 = status.root_position
		position.x = root.x
		position.z = root.z
	if flying and is_hero():
		if air_sink > 0:
			var drop := minf(air_sink, air_sink_speed * delta)
			move_and_collide(Vector3.DOWN * drop)
			air_sink -= drop
		var probe := Vector3(position.x, maxf(previous_position.y, position.y), position.z)
		var surface := simulation._movement_surface(probe)
		if is_finite(surface):
			var hover: float = surface + (Content.constants.FLIGHT.HOVER_M if kind == "drone" else 0)
			position.y = maxf(hover, minf(position.y, minf(surface + Content.constants.TARGET_H.tower * Content.constants.FLIGHT.ALT_TOP_F, simulation.world.ceiling)))
			if position.y <= hover:
				air_sink = 0
				velocity.y = maxf(0, velocity.y)
			if kind == "morph" and velocity.y <= 0 and position.y <= surface + Content.constants.MORPH.LAND_M:
				flying = false
				position.y = surface
				velocity.y = 0
				impulse_velocity = Vector2(velocity.x, velocity.z)
				refresh_collision()
				simulation.request_iframe(self)
	elif is_on_floor():
		low_gravity = false
	var ice_ceiling: Variant = simulation._ice_ceiling(previous_position)
	if ice_ceiling != null:
		var cap := float(ice_ceiling) - height - 0.2
		if position.y > cap and position.y > previous_position.y:
			position.y = maxf(previous_position.y, cap)
			velocity.y = minf(0, velocity.y)
	simulation._update_fluid_state(self)
	jump_was_held = held
	sync_view_camera()
	if animation_player != null and Time.get_ticks_msec() / 1000.0 > animation_until:
		var clip := "run" if motion.length() > 0.01 else "idle"
		if animation_player.has_animation(clip) and animation_player.current_animation != clip:
			animation_player.play(clip, 0.12)

func _step_lift(simulation: BattleSimulation, vertical: float, delta: float) -> float:
	var stats: Dictionary = Content.constants.UNITS[kind]
	var reference := float(simulation.world.water_y) if simulation.world != null and simulation.world.water_y != null else simulation.world.native_data.min_height if simulation.world != null and simulation.world.native_data != null else NAN
	var unbalanced := flying and (air_sink > 0 or lift_lock_until > simulation.clock or has_status("unbalanced_until", simulation.clock))
	var state := MovementRules.step_lift(lift, vertical, position.y, reference, float(stats.get("vspeed", 0)),
		float(stats.get("vdown", stats.get("vspeed", 0))), delta, unbalanced, StatusRules.fluid_factor(wet), WeatherRules.air_lift(simulation.weather_dynamics))
	lift = state.lift
	return state.vertical

func _launch_charged_jump(simulation: BattleSimulation) -> void:
	var morph := kind == "morph"
	var minimum: float = Content.constants.MORPH.JUMP_MIN if morph else Content.constants.CJUMP.MIN
	var free := defending and has_status("def_jump_until", simulation.clock)
	var cost := 0.0 if free else MovementRules.jump_cost(charge, morph)
	if lift < 0:
		lift = Content.constants.FLIGHT.LIFT_MAX
	var jump_factor := simulation._terrain_jump_velocity(self) * WeatherRules.jump_velocity(simulation.weather_surface)
	if charge >= minimum and lift >= cost:
		lift = maxf(0, lift - cost)
		if morph:
			flying = true
			velocity = Vector3(impulse_velocity.x, Content.constants.MORPH.JUMP_V * charge * jump_factor, impulse_velocity.y)
			move_and_collide(Vector3.UP)
			refresh_collision()
		else:
			velocity.y = Content.constants.CJUMP.V * charge * StatusRules.movement_modifier(buffs, "jump", simulation.clock) * jump_factor
			low_gravity = true
			var forward := Vector2(-sin(yaw), -cos(yaw))
			var momentum: float = speed * StatusRules.movement_modifier(buffs, "speed", simulation.clock) * Content.constants.CJUMP.FWD_F * Content.constants.CJUMP.AIR_SPD_F * charge
			if has_status("sup_until", simulation.clock):
				momentum *= 1 - Content.constants.HIGH_SUP.SPEED * float(status.get("sup_factor", 0))
			impulse_velocity += forward * momentum
		simulation.request_iframe(self)
	else:
		velocity.y = float(Content.constants.UNITS[kind].get("jump", 0)) * StatusRules.movement_modifier(buffs, "jump", simulation.clock) * jump_factor
	charge = 0

func play_action(action: String) -> void:
	if animation_player != null and animation_player.has_animation(action):
		animation_player.play(action, 0.05)
		animation_until = Time.get_ticks_msec() / 1000.0 + animation_player.get_animation(action).length

func apply_snapshot(state: Dictionary, instant: bool = false) -> void:
	var previous_flight := flying
	var was_alive := alive()
	var was_collapsed := bool(special.get("collapsed", false))
	var was_garrison := bool(special.get("garrison", false))
	hp = state.hp
	max_hp = state.max_hp
	shield = state.shield
	max_shield = state.max_shield
	power = state.power
	money = state.money
	score = state.score
	deaths = state.deaths
	ammo = state.ammo
	upgrades = state.upgrades
	reload_at = state.reload_at
	cooldowns = state.cooldowns
	status = state.get("status", {}).duplicate(true)
	buffs = state.get("buffs", []).duplicate(true)
	wet = int(state.get("wet", 0))
	fluid_environment = state.get("fluid_environment", {}).duplicate(true)
	cast_state = state.get("cast", {}).duplicate(true)
	ability_charges = state.get("ability_charges", {}).duplicate(true)
	defending = state.get("defending", false)
	special = state.get("special", {}).duplicate(true)
	if was_garrison != bool(special.get("garrison", false)):
		refresh_collision()
	if special.get("role") == "hazard" and special.get("collapsed", false) and not was_collapsed:
		apply_collapse(instant)
		refresh_collision()
	creep_multiplier = float(state.get("creep_multiplier", 1))
	charge = state.get("charge", 0)
	lift = state.get("lift", Content.constants.FLIGHT.LIFT_MAX)
	respawn_at = state.respawn_at
	flying = state.flying
	view_offset = state.get("view_offset", Vector3.ZERO)
	view_offset_ready = state.has("view_offset")
	if previous_flight != flying or was_alive != alive():
		refresh_collision()
	target_position = state.position
	target_yaw = state.yaw
	yaw = state.yaw
	pitch = state.pitch
	if instant:
		global_position = target_position
		rotation.y = target_yaw
	visible = (alive() or special.get("collapsed", false)) and not special.get("garrison", false)
	if camera != null:
		camera.rotation.x = pitch
		sync_view_camera()

func interpolate(delta: float) -> void:
	global_position = global_position.lerp(target_position, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))
	sync_view_camera()

func apply_collapse(instant: bool = false) -> void:
	if model == null:
		return
	var original_scale := model.scale
	var original_rotation := model.rotation
	var pose := func(fraction):
		var state := SceneRules.collapse_pose(entity_id, original_scale, original_rotation, fraction)
		model.scale = state.scale
		model.rotation = state.rotation
	if instant:
		pose.call(1.0)
	else:
		create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_method(pose, 0.0, 1.0, 0.7)

func snapshot() -> Dictionary:
	var public_special := special.duplicate(true)
	if special.get("role") == "civilian":
		public_special = {"role": "civilian", "neutral": true, "civil_side": special.civil_side, "profession": special.profession,
			"following": special.get("following", int(special.get("follow_peer", 0)) != 0), "fleeing": special.get("fleeing", special.get("flee", false))}
	return {"id": entity_id, "peer": peer_id, "side": side, "kind": kind, "character": character,
		"special": public_special,
		"effect_radius": effect_radius,
		"creep_multiplier": creep_multiplier,
		"wet": wet, "fluid_environment": fluid_environment.duplicate(true),
		"lane": lane, "has_lane": has_lane, "bot": is_bot, "position": global_position, "yaw": yaw, "pitch": pitch,
		"hp": hp, "max_hp": max_hp, "shield": shield, "max_shield": max_shield,
		"power": power, "money": money, "score": score, "deaths": deaths,
		"ammo": ammo.duplicate(), "upgrades": upgrades.duplicate(), "reload_at": reload_at.duplicate(),
		"cooldowns": cooldowns.duplicate(), "respawn_at": respawn_at, "flying": flying,
		"status": status.duplicate(true), "defending": defending,
		"buffs": buffs.duplicate(true),
		"charge": charge, "lift": lift,
		"cast": {"slot": cast_state.slot, "start": cast_state.start, "duration": cast_state.duration} if not cast_state.is_empty() else {},
		"ability_charges": ability_charges.duplicate(true),
		"view_offset": Basis(Vector3.UP, -yaw) * (view_origin() - global_position) if is_pilot() else Vector3.ZERO}
